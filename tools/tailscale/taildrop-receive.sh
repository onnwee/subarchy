#!/usr/bin/env bash
# Installed as /usr/lib/subcult/taildrop-receive; subcult-taildrop@<user>.service
# runs it as root (ADR 0058). Files sent to this machine with Taildrop land
# in the user's ~/Downloads (a taken name gets -1, -2 ...) and each is
# announced. tailscaled hands Taildrop files only to root or its operator,
# and Subarchy makes no one the operator (ADR 0062), so the receiving side
# is root's.
#
#   taildrop-receive [--once] USER     receive for USER (root)
#   taildrop-receive --deliver NAME    save standard input as NAME in
#                                      ~/Downloads (run as the user)
#
# Root keeps the files in its own folder, $STATE_DIRECTORY (systemd's
# StateDirectory, mode 0700), and never writes in the user's home: each file
# goes over as standard input to --deliver, run as the user with setpriv,
# so a link the user planted in their home cannot point root's writes
# anywhere.
set -euo pipefail

# claim STAGED NAME: hard-link STAGED to a free name in $dir based on NAME,
# then drop STAGED. link(2) fails on a taken name, so nothing is overwritten
# even when another program writes to Downloads at the same time. A link
# that points nowhere also takes its name, and so does a folder or a link
# to one (-T: never a link inside it). A numbered name is shortened, in
# whole characters, to stay within 255 bytes. Prints the path it took.
claim() {
  local staged=$1 name=$2 base ext target i
  base=${name%.*}
  ext=${name:${#base}}
  [[ -n $base ]] || { base=$name ext=; }
  for ((i = 0; i < 1000; i++)); do
    target=$name
    if ((i)); then
      while ! fits "$base-$i$ext"; do
        if [[ -n $base ]]; then base=$(shorten "$base"); else base=$name ext=; fi
      done
      target=$base-$i$ext
    fi
    if ln -T -- "$staged" "$dir/$target" 2>/dev/null; then
      rm -f -- "$staged"
      printf '%s\n' "$dir/$target"
      return 0
    fi
    [[ -e $dir/$target || -L $dir/$target ]] || return 1
  done
  return 1
}
fits() {
  local LC_ALL=C
  ((${#1} <= 255))
}
shorten() {
  local LC_ALL=C.UTF-8
  printf '%s' "${1%?}"
}

# The user's side: copy standard input to a hidden file in Downloads, then
# give it its name. A copy cut off halfway stays hidden.
if [[ ${1:-} == --deliver ]]; then
  name=${2:?usage: taildrop-receive --deliver NAME}
  [[ $name != */* && $name != . && $name != .. ]] || { echo "taildrop-receive: bad name: $name" >&2; exit 1; }
  dir=$HOME/Downloads
  tmp=
  trap 'rm -f -- "$tmp"' EXIT
  # A file that cannot be saved stays with root and comes again with the
  # next file received; the user hears about it each time.
  if ! { mkdir -p -- "$dir" && tmp=$(mktemp -- "$dir/.taildrop-XXXXXX") && cat >"$tmp" &&
    chmod 0644 -- "$tmp" && target=$(claim "$tmp" "$name"); }; then
    notify-send -a Taildrop -u critical -i dialog-error -- "Could not save $name" \
      "Taildrop will try again when the next file arrives" 2>/dev/null || true
    exit 1
  fi
  notify-send -a Taildrop -i folder-download -- "Received ${target##*/}" "Saved to ~/Downloads" 2>/dev/null || true
  exit 0
fi

once=0
if [[ ${1:-} == --once ]]; then
  once=1
  shift
fi
user=${1:?usage: taildrop-receive [--once] USER}
uid=$(id -u -- "$user")
gid=$(id -g -- "$user")
spool=${STATE_DIRECTORY:?taildrop-receive runs from subcult-taildrop@.service, which sets STATE_DIRECTORY}
retry=${SUBCULT_TAILDROP_RETRY:-60}
self=${BASH_SOURCE[0]}

# --deliver as the user, with their session bus for the notification.
as_user() {
  setpriv --reuid="$uid" --regid="$gid" --init-groups --reset-env -- \
    env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# Hands the files in every done.* folder to the user. A file that cannot be
# placed stays for the next round.
deliver() {
  local batch staged
  for batch in "$spool"/done.*; do
    [[ -d $batch ]] || continue
    while IFS= read -r -d '' staged; do
      if as_user "$self" --deliver "${staged##*/}" <"$staged"; then
        rm -f -- "$staged"
      fi
    done < <(find "$batch" -mindepth 1 -maxdepth 1 -type f -print0)
    rmdir -- "$batch" 2>/dev/null || true
  done
}

# keep GET RECORDS: save what a get that did not finish wrote. `tailscale
# file get` writes each file under its final name, closes it, prints
# "wrote NAME as PATH (N bytes)" (--verbose) and only then drops it from
# tailscaled's inbox, one file at a time, whether or not that line could be
# written. RECORDS is that output: kept in memory for a get this run made,
# so a full disk cannot cut it short, and read back from GET.log for one an
# earlier run left. A file it names is whole and may be gone from the
# inbox, so it is kept. Any other file was cut off halfway and is still in
# the inbox; it comes again, so it is dropped. GET then becomes a done.*
# folder by a rename, which needs no new space; if even that fails, it
# stays for the next start.
keep() {
  local get=$1 line name file
  local -A whole=()
  while IFS= read -r line; do
    # "waiting for file..." has no line end, so a line can start with it.
    [[ $line == *" as $get/"*" bytes)" ]] || continue
    name=${line#*" as $get/"}
    name=${name%" ("*" bytes)"}
    # A leading / keeps a name such as @ from reading as the whole array.
    [[ -z $name || $name == */* ]] || whole[/$name]=1
  done < <(printf '%s\n' "$2")
  while IFS= read -r -d '' file; do
    if [[ -z ${whole[/${file##*/}]+x} || -L $file || ! -f $file ]]; then
      rm -rf -- "$file"
    fi
  done < <(find "$get" -mindepth 1 -maxdepth 1 -print0)
  mv -T -- "$get" "$spool/done.${get##*/get.}" || return 0
  rm -f -- "$get.log"
}

# Each get writes into its own get.* folder, renamed to done.* once it has
# succeeded. A get that failed, or one an earlier run left when it was
# stopped, keeps the files it finished. It is `--wait` once per round and
# not `--loop`: the end of a get is what says its files are whole.
for get in "$spool"/get.*; do
  [[ -d $get ]] || continue
  records=
  if [[ -f $get.log ]]; then records=$(<"$get.log"); fi
  keep "$get" "$records"
done
for log in "$spool"/get.*.log; do
  [[ -d ${log%.log} ]] || rm -f -- "$log"
done
deliver
last=
while true; do
  get=$(mktemp -d "$spool/get.XXXXXX")
  # The output goes to memory, for keep, and to GET.log, for the next start
  # should this one be stopped halfway. Errors come in the same stream.
  if out=$(
    tailscale file get --wait --verbose --conflict=rename "$get" 2>&1 | tee -- "$get.log" 2>/dev/null
    exit "${PIPESTATUS[0]}"
  ); then
    mv -- "$get" "$spool/done.${get##*/get.}"
    rm -f -- "$get.log"
    last=
    deliver
    ((once)) && exit 0
    continue
  fi
  keep "$get" "$out"
  deliver
  # The error is the output without the file records. Signed out,
  # tailscaled refuses at once ("no storage directory"); the same refusal
  # is logged once.
  err=
  while IFS= read -r line; do
    line=${line#waiting for file...}
    [[ -z $line || $line == "wrote "*" as $get/"*" bytes)" ]] || err+=${err:+$'\n'}$line
  done < <(printf '%s\n' "$out")
  [[ $err == "$last" ]] || echo "taildrop-receive: $err" >&2
  last=$err
  ((once)) && exit 1
  # `tailscale wait` sleeps until tailscaled is connected (no polling), so
  # a sign-in is picked up within $retry seconds.
  tailscale wait >/dev/null 2>&1 || true
  sleep "$retry" &
  wait $!
done
