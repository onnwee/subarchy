#!/usr/bin/env bash
# `subcult docker tui` (ADR 0055) with stand-ins for pkexec and lazydocker:
# without access to the Docker socket it goes through pkexec to the root
# side the polkit action names, passing only the terminal type; with access
# (sudoless Docker) it runs lazydocker directly. The root side keeps a sane
# terminal type and drops anything else.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "docker-tui-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export PATH="$work/bin:$PATH"
cat >"$work/bin/pkexec" <<'STUB'
#!/bin/sh
echo "pkexec $*"
STUB
cat >"$work/bin/lazydocker" <<'STUB'
#!/bin/sh
echo "lazydocker TERM=$TERM $*"
STUB
chmod +x "$work/bin/pkexec" "$work/bin/lazydocker"

action=$(grep -o '<annotate key="org.freedesktop.policykit.exec.path">[^<]*' "$root/default/polkit/tv.subcult.docker.policy" | sed 's/.*>//')

# No socket the user can write (a missing one, so the test means the same
# as root).
sock=$work/docker.sock
out=$(SUBCULT_DOCKER_SOCKET=$sock TERM=xterm-kitty "$root/bin/subcult-docker-tui")
[[ $out == "pkexec $action xterm-kitty" ]] || fail "without socket access: $out (action $action)"

touch "$sock"
out=$(SUBCULT_DOCKER_SOCKET=$sock TERM=xterm-kitty "$root/bin/subcult-docker-tui")
[[ $out == "lazydocker TERM=xterm-kitty " ]] || fail "with socket access: $out"

# The root side: lazydocker by absolute path, so test only its argument
# check by reading what it would exec.
# shellcheck disable=SC2016  # the literal line in the script
grep -qx 'exec env TERM="$term" /usr/bin/lazydocker' "$root/tools/docker/lazydocker-root.sh" || fail "root side does not run /usr/bin/lazydocker"
term_of() {
  bash -c 'f=$1; shift; source <(sed "s|^exec env TERM=\"\$term\" /usr/bin/lazydocker|echo \"\$term\"|" "$f")' \
    _ "$root/tools/docker/lazydocker-root.sh" "$@"
}
[[ $(term_of xterm-kitty) == xterm-kitty ]] || fail "a plain terminal type was changed"
[[ $(term_of 'x;evil') == xterm-256color ]] || fail "a bad terminal type was passed on"
[[ $(term_of) == xterm-256color ]] || fail "no terminal type"
echo "docker-tui-test: ok"
