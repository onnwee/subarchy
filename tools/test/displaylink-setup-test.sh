#!/usr/bin/env bash
# `subcult setup displaylink` against stand-ins for sudo, pacman, systemctl,
# notify-send and the terminal: it installs the drivers and headers through
# sudo only when some are missing, always enables displaylink.service, and
# --offer notifies only when the drivers are missing and opens the setup in
# a terminal only when the button is pressed (#196).
# shellcheck disable=SC2016 # the stand-ins' bodies expand when they run
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cmd=$root/bin/subcult-setup-displaylink
fail() { echo "displaylink-setup-test: $*" >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo "displaylink-setup-test: the command refuses root, skipped"; exit 0; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export DL_TEST="$work"

stub() {
  printf '#!/bin/bash\necho "%s $*" >>"$DL_TEST/calls"\n%s\n' "$1" "$2" >"$work/bin/$1"
  chmod +x "$work/bin/$1"
}
stub sudo 'exec "$@"'
# pacman -T prints the packages not listed in $DL_TEST/installed.
stub pacman ''
cat >>"$work/bin/pacman" <<'STUB'
if [[ $1 == -T ]]; then
  shift
  rc=0
  have=
  [[ ! -e $DL_TEST/installed ]] || have=$(<"$DL_TEST/installed")
  for p; do [[ $'\n'$have$'\n' == *$'\n'$p$'\n'* ]] || { echo "$p"; rc=127; }; done
  exit $rc
fi
STUB
stub systemctl ''
stub notify-send '[[ ! -e $DL_TEST/pressed ]] || echo install'
stub xdg-terminal-exec ''

fresh() { rm -f "$work"/{calls,installed,pressed}; : >"$work/calls"; }
run() { PATH="$work/bin" /bin/bash "$cmd" "$@" >"$work/out" 2>&1; }
called() { grep -q -- "$1" "$work/calls"; }

# Nothing installed: drivers and headers through sudo, then the service.
fresh
run || fail "setup failed: $(<"$work/out")"
called 'sudo pacman -S --needed --noconfirm evdi-dkms displaylink linux-zen-headers linux-lts-headers' ||
  fail "drivers not installed through sudo: $(tr '\n' ';' <"$work/calls")"
called 'sudo systemctl enable --now displaylink.service' || fail "displaylink.service not enabled"

# Everything installed: no pacman -S, the service is still enabled.
fresh
printf '%s\n' evdi-dkms displaylink linux-zen-headers linux-lts-headers >"$work/installed"
run || fail "setup with the drivers installed failed"
called 'pacman -S' && fail "installed packages again"
called 'systemctl enable --now displaylink.service' || fail "service not enabled when already installed"

# --offer with the drivers there: no notification.
fresh
printf '%s\n' evdi-dkms displaylink >"$work/installed"
run --offer || fail "offer failed"
called notify-send && fail "offered drivers that are installed"

# --offer without them: a notification; the terminal only on the button.
fresh
run --offer || fail "offer failed"
called notify-send || fail "no notification"
called xdg-terminal-exec && fail "opened a terminal without the button"
fresh
: >"$work/pressed"
run --offer || fail "offer failed"
called 'xdg-terminal-exec subcult setup displaylink' || fail "the button did not open the setup"
called 'pacman -S' && fail "--offer installed packages itself"

if run bogus; then fail "accepted an unknown argument"; fi
echo "displaylink-setup-test: ok"
