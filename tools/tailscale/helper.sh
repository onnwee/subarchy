#!/usr/bin/env bash
# Installed as /usr/lib/subcult/tailscale-helper and named by the polkit
# action tv.subcult.tailscale (ADR 0058, ADR 0062). pkexec runs it as root
# for the bar's Tailscale panel and `subcult tailscale send`, so the user
# needs no operator rights in tailscaled. It runs tailscale with fixed
# flags and nothing else:
#
#   up                  connect with the saved settings
#   login               sign in: print the sign-in link and leave
#   down                disconnect
#   exit-node ADDRESS   use the machine at this Tailscale address as the
#                       exit node, keeping the local network reachable;
#                       an empty ADDRESS stops using one and puts both
#                       settings back to their defaults
#   send ADDRESS NAME   send standard input with Taildrop as NAME
#
# ADDRESS is a Tailscale IPv4 (100.64.0.0/10) or IPv6 (fd7a:115c:a1e0::/48)
# address. The helper never opens a path the caller names: `send` reads the
# file from standard input, which the caller opened.
set -euo pipefail

die() { echo "tailscale-helper: $*" >&2; exit 2; }
usage="usage: tailscale-helper up | login | down | exit-node ADDRESS | send ADDRESS NAME"

octet='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
tailscale_ip() {
  [[ $1 =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.$octet\.$octet$ ]] ||
    { [[ $1 =~ ^fd7a:115c:a1e0:[0-9a-f:]{1,24}$ && $1 != *:::* ]]; }
}

# A file name Taildrop can take: no folder, no control characters.
file_name() {
  local LC_ALL=C
  [[ -n $1 && $1 != . && $1 != .. && $1 != */* && $1 != *[[:cntrl:]]* ]] && ((${#1} <= 255))
}

# The flags that keep the helper's own settings (the exit node and access
# to the local network) when `tailscale up` is not a plain connect. Signed
# out (no account, or the sign-in expired) with a coordination server
# already set, `tailscale up` puts every setting it is not given back to
# its default and refuses when that would undo one made before, unless the
# command repeats it. Signed in, plain `tailscale up` only connects, and
# any flag would make it check every setting again, so nothing is added.
# Before the first sign-in there is no check: `tailscale up` resets every
# setting to its default (ADR 0062). jq comes with every install
# (install/packages/cli.txt); without it nothing is added.
restate() {
  local prefs state ip lan
  prefs=$(tailscale debug prefs) || return 0
  state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // ""') || state=
  [[ -n $(jq -r '.ControlURL // ""' <<<"$prefs") ]] || return 0
  if [[ -n $(jq -r '.Config.UserProfile.LoginName // ""' <<<"$prefs") && $state != NeedsLogin ]]; then
    return 0
  fi
  # As `tailscale up` reads it: ExitNodeIP, or else the address of the
  # machine ExitNodeID names, if tailscaled still knows it.
  ip=$(jq -r '.ExitNodeIP // ""' <<<"$prefs")
  if [[ -z $ip ]]; then
    ip=$(tailscale status --json 2>/dev/null | jq -r --arg id "$(jq -r '.ExitNodeID // ""' <<<"$prefs")" \
      'if $id == "" then "" else ([.Peer[]? | select(.ID == $id) | .TailscaleIPs[0]] | first // "") end') || ip=
  fi
  lan=$(jq -r '.ExitNodeAllowLANAccess // false' <<<"$prefs")
  if [[ -n $ip ]] && tailscale_ip "$ip"; then
    flags+=(--exit-node="$ip")
    [[ $lan != true ]] || flags+=(--exit-node-allow-lan-access=true)
  elif [[ $lan == true ]]; then
    # No exit node it can name (tailscaled no longer knows the machine's
    # address), and `tailscale up` takes the local-network flag only with
    # one: drop both, as `tailscale up` would drop the exit node anyway.
    tailscale set --exit-node= --exit-node-allow-lan-access=false
  fi
}

# `tailscale up` prints a sign-in link when tailscaled has no account and
# then waits for the browser. The pending sign-in and its link stay in
# tailscaled after `tailscale up` stops (seen with 1.104.7), and the
# browser completes it there, so this stops waiting at the link: the
# caller's panel watches `tailscale status` instead. With an account, up
# connects and exits.
up() {
  local mode=$1 line text='' url='' status=0 pid out flags=()
  restate
  exec {out}< <(exec tailscale up "${flags[@]}" 2>&1)
  pid=$!
  while true; do
    IFS= read -r -t 60 -u "$out" line || { status=$?; break; }
    text+=$line$'\n'
    if [[ $line =~ (https://[^[:space:]]+) ]]; then
      url=${BASH_REMATCH[1]}
      break
    fi
  done
  if [[ -n $url ]]; then
    kill "$pid" 2>/dev/null || true
    if [[ $mode == login ]]; then
      printf '%s\n' "$url"
      exit 0
    fi
    echo "Signed out: sign in first" >&2
    exit 1
  fi
  if ((status > 128)); then
    kill "$pid" 2>/dev/null || true
    echo "tailscale up did not answer within a minute" >&2
    exit 1
  fi
  wait "$pid" && exit 0
  status=$?
  printf '%s' "$text" >&2
  exit "$status"
}

(($# >= 1)) || die "$usage"
verb=$1
shift
case $verb in
up | login)
  (($# == 0)) || die "$usage"
  up "$verb"
  ;;
down)
  (($# == 0)) || die "$usage"
  exec tailscale down
  ;;
exit-node)
  (($# == 1)) || die "$usage"
  [[ -z $1 ]] && exec tailscale set --exit-node= --exit-node-allow-lan-access=false
  tailscale_ip "$1" || die "not a Tailscale address: $1"
  exec tailscale set --exit-node="$1" --exit-node-allow-lan-access=true
  ;;
send)
  (($# == 2)) || die "$usage"
  tailscale_ip "$1" || die "not a Tailscale address: $1"
  file_name "$2" || die "not a file name: $2"
  exec tailscale file cp --update-interval=0 --name="$2" - "$1:"
  ;;
*)
  die "$usage"
  ;;
esac
