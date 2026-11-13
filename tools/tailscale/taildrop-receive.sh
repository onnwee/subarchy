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
# that points nowhere also takes its name. A numbered name is shortened, in
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
    if ln -- "$staged" "$dir/$target" 2>/dev/null; then
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

# Hands the files of every finished get to the user. A file that cannot be
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

# `tailscale file get` writes each file under its final name and then drops
# it from tailscaled's inbox, so a get stopped halfway leaves a cut-off
# file. Each get therefore writes into its own get.* folder, renamed to
# done.* only once it has succeeded. A get.* folder found later is thrown
# away: its files are still in the inbox and come again. This is also why
# it is `--wait` once per round and not `--loop`: the end of a get is what
# says its files are whole.
rm -rf -- "$spool"/get.*
deliver
last=
while true; do
  get=$(mktemp -d "$spool/get.XXXXXX")
  if err=$(tailscale file get --wait --conflict=rename "$get" 2>&1 >/dev/null); then
    mv -- "$get" "$spool/done.${get##*/get.}"
    last=
    deliver
    ((once)) && exit 0
    continue
  fi
  rm -rf -- "$get"
  # Signed out, tailscaled refuses at once ("no storage directory"); the
  # same refusal is logged once.
  [[ $err == "$last" ]] || echo "taildrop-receive: $err" >&2
  last=$err
  ((once)) && exit 1
  # `tailscale wait` sleeps until tailscaled is connected (no polling), so
  # a sign-in is picked up within $retry seconds.
  tailscale wait >/dev/null 2>&1 || true
  sleep "$retry" &
  wait $!
done
