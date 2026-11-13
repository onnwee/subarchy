#!/usr/bin/env bash
# The root helper behind the polkit action tv.subcult.tailscale (ADR 0058,
# ADR 0062), with a stand-in for tailscale. It runs up, down, the sign-in,
# the exit node and a Taildrop send with fixed flags, takes only Tailscale
# addresses and plain file names, refuses everything else without calling
# tailscale, and stops waiting at the sign-in link. Signed out after an
# earlier sign-in, up and the sign-in repeat the exit node it set, so
# `tailscale up` does not refuse; clearing the exit node clears both of
# its settings. The polkit action names
# it and lets the active session run it without a password.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
helper=$root/tools/tailscale/helper.sh
fail() { echo "tailscale-helper-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export TS_TEST="$work" PATH="$work/bin:$PATH"

cat >"$work/bin/tailscale" <<'STUB'
#!/bin/bash
# Reading (prefs, status) is not logged; it changes nothing.
case "$1 ${2:-}" in
"debug prefs") cat "$TS_TEST/prefs" 2>/dev/null || echo '{}'; exit 0;;
"status --json") cat "$TS_TEST/status" 2>/dev/null || echo '{}'; exit 0;;
esac
echo "$*" >>"$TS_TEST/calls"
case "$1 ${2:-}" in
"up "*)
  case $(cat "$TS_TEST/up-mode" 2>/dev/null) in
  signed-out) printf '\nTo authenticate, visit:\n\n\thttps://login.tailscale.com/a/abc123\n\n' >&2; sleep 30;;
  fails) echo "backend error: boom" >&2; exit 3;;
  esac;;
"file cp") cat >"$TS_TEST/sent";;
esac
exit 0
STUB
chmod +x "$work/bin/tailscale"

calls() { cat "$work/calls" 2>/dev/null || true; }
ok() {
  rm -f "$work/calls"
  "$helper" "$@" </dev/null >/dev/null || fail "refused: $*"
}
refused() {
  rm -f "$work/calls"
  if "$helper" "$@" </dev/null >/dev/null 2>&1; then fail "accepted: $(printf '[%s] ' "$@")"; fi
  [[ -z $(calls) ]] || fail "ran tailscale for $(printf '[%s] ' "$@"): $(calls)"
}

# Fixed command lines.
ok down
[[ $(calls) == down ]] || fail "down: $(calls)"
ok exit-node 100.64.0.2
[[ $(calls) == 'set --exit-node=100.64.0.2 --exit-node-allow-lan-access=true' ]] || fail "exit node: $(calls)"
ok exit-node 100.127.255.254
ok exit-node fd7a:115c:a1e0::3
[[ $(calls) == 'set --exit-node=fd7a:115c:a1e0::3 --exit-node-allow-lan-access=true' ]] || fail "IPv6 exit node: $(calls)"
ok exit-node ''
[[ $(calls) == 'set --exit-node= --exit-node-allow-lan-access=false' ]] || fail "clearing the exit node: $(calls)"

# Anything else is refused before tailscale runs.
refused
refused set --ssh
refused status
refused down --accept-routes
refused up --ssh
refused login --operator=alice
refused up --operator alice
refused down --operator=alice
refused exit-node --operator=alice
refused exit-node 100.64.0.2 --operator=alice
refused send --operator=alice 100.64.0.4 a.txt
refused --operator=alice up
refused exit-node
refused exit-node 100.64.0.2 extra
for addr in 10.0.0.1 100.63.255.1 100.128.0.1 100.64.0.256 100.64.0 '100.64.0.2 --ssh' --ssh '100.64.0.2,' \
  kvant kvant.tail1.ts.net fd7a:115c:a1e1::3 'fd7a:115c:a1e0:::3' 'FD7A:115C:A1E0::3' $'100.64.0.2\n'; do
  refused exit-node "$addr"
  refused send "$addr" notes.txt
done

# Taildrop: standard input goes to `tailscale file cp` under the name.
rm -f "$work/calls"
printf 'payload' | "$helper" send 100.64.0.4 'a file.pdf' >/dev/null || fail "send refused"
[[ $(calls) == 'file cp --update-interval=0 --name=a file.pdf - 100.64.0.4:' ]] || fail "send: $(calls)"
[[ $(<"$work/sent") == payload ]] || fail "send did not pass standard input"
for name in '' . .. ../etc/passwd a/b /etc/shadow $'a\nb' $'a\tb' "$(printf 'x%.0s' {1..256})"; do
  refused send 100.64.0.4 "$name"
done
refused send 100.64.0.4
refused send 100.64.0.4 a.txt extra
ok send 100.64.0.4 "$(printf 'x%.0s' {1..255})"
ok send 100.64.0.4 .hidden

# Sign-in: the link, at once, and tailscale up is not left behind.
echo signed-out >"$work/up-mode"
start=$SECONDS
out=$("$helper" login) || fail "login failed"
[[ $out == https://login.tailscale.com/a/abc123 ]] || fail "login printed: $out"
((SECONDS - start < 10)) || fail "login waited for the browser"
if pgrep -f "$work/bin/tailscale up" >/dev/null; then fail "tailscale up left running"; fi
# up signed out: no link on standard output, a failure that says why.
if out=$("$helper" up 2>"$work/err"); then fail "up succeeded while signed out"; fi
[[ -z $out && $(<"$work/err") == 'Signed out: sign in first' ]] || fail "up signed out: [$out] $(<"$work/err")"
# Signed in: up connects and exits; login does the same with nothing to print.
echo >"$work/up-mode"
out=$("$helper" up) || fail "up failed"
[[ -z $out ]] || fail "up printed: $out"
out=$("$helper" login) || fail "login failed while signed in"
[[ -z $out ]] || fail "login printed while signed in: $out"
# A failure passes tailscale's words and status on.
echo fails >"$work/up-mode"
status=0
"$helper" up 2>"$work/err" >/dev/null || status=$?
[[ $status == 3 ]] || fail "up failure status: $status"
grep -qx 'backend error: boom' "$work/err" || fail "up failure text: $(<"$work/err")"

# Signed out with a coordination server set (a sign-in that expired or was
# signed out), `tailscale up` must repeat the helper's own settings or it
# refuses; signed in, or before the first sign-in, it gets no flags.
echo >"$work/up-mode"
prefs() { printf '{"ControlURL":"%s","ExitNodeIP":"%s","ExitNodeID":"%s","ExitNodeAllowLANAccess":%s,"Config":%s}' "$@" >"$work/prefs"; }
state() { printf '{"BackendState":"%s","Peer":{"k":{"ID":"n7","TailscaleIPs":["100.64.0.7","fd7a:115c:a1e0::7"]}}}' "$1" >"$work/status"; }
cs=https://controlplane.tailscale.com signedin='{"UserProfile":{"LoginName":"me@example.com"}}'
up_calls() { rm -f "$work/calls"; "$helper" "$1" >/dev/null || fail "$1 failed: $(calls)"; calls; }
prefs "$cs" 100.64.0.9 '' true null; state NeedsLogin
[[ $(up_calls login) == 'up --exit-node=100.64.0.9 --exit-node-allow-lan-access=true' ]] || fail "exit node kept: $(calls)"
[[ $(up_calls up) == 'up --exit-node=100.64.0.9 --exit-node-allow-lan-access=true' ]] || fail "up, exit node kept: $(calls)"
prefs "$cs" '' n7 false "$signedin"; state NeedsLogin
[[ $(up_calls login) == 'up --exit-node=100.64.0.7' ]] || fail "exit node by ID: $(calls)"
prefs "$cs" '' '' true null; state NeedsLogin
[[ $(up_calls login) == $'set --exit-node= --exit-node-allow-lan-access=false\nup' ]] ||
  fail "local network without an exit node: $(calls)"
prefs "$cs" '' n9 true null; state NeedsLogin
[[ $(up_calls login) == $'set --exit-node= --exit-node-allow-lan-access=false\nup' ]] ||
  fail "an exit node tailscaled no longer knows: $(calls)"
prefs "$cs" '--ssh' '' false null; state NeedsLogin
[[ $(up_calls login) == up ]] || fail "a stored exit node that is not an address: $(calls)"
prefs "$cs" 100.64.0.9 '' true "$signedin"; state Stopped
[[ $(up_calls up) == up ]] || fail "signed in, up added flags: $(calls)"
prefs '' 100.64.0.9 '' true null; state NoState
[[ $(up_calls login) == up ]] || fail "before the first sign-in, login added flags: $(calls)"
rm -f "$work/prefs" "$work/status"

# The polkit action: this helper, without a password for the active session only.
policy=$root/default/polkit/tv.subcult.tailscale.policy
grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/lib/subcult/tailscale-helper</annotate>' "$policy" ||
  fail "the polkit action does not name the helper"
{ grep -q '<allow_active>yes</allow_active>' "$policy" && grep -q '<allow_inactive>auth_admin</allow_inactive>' "$policy" &&
  grep -q '<allow_any>auth_admin</allow_any>' "$policy"; } || fail "polkit defaults"
if command -v xmllint >/dev/null; then xmllint --noout "$policy" || fail "the polkit action is not well-formed"; fi
echo "tailscale-helper-test: ok"
