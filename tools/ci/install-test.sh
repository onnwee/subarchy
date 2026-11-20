#!/usr/bin/env bash
# Run as root in the job container after tools/ci/build-iso.sh. Installs
# from the image that script built into a QEMU disk, then boots the disk and
# runs every check of tools/iso/install-test.py (issue #68).
#
# full: the guided, offline install: the image's own setup command,
# installer and repository, with the guest's network off. That is what a
# person installs from, and the result does not depend on a mirror answering.
# net: the guided install from the network-install image (#329), online.
#
# Usage: install-test.sh [full|net]   (default full)
set -euo pipefail

edition=${1:-full}
case $edition in
  full) mode=--offline ;;
  net) mode=--net ;;
  *) echo "install-test: unknown image $edition (full or net)" >&2; exit 1 ;;
esac
root=$(git rev-parse --show-toplevel)
pacman -S --noconfirm --needed qemu-img swtpm imagemagick
isos=("$root"/build/iso/subarchy-"$edition"-*.iso)
cd "$root"
python3 tools/iso/install-test.py --guided "$mode" "${isos[0]}"
