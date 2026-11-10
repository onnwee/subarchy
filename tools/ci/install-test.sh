#!/usr/bin/env bash
# Run as root in the job container after tools/ci/build-iso.sh. Installs
# from the image that script built into a QEMU disk, then boots the disk and
# runs every check of tools/iso/install-test.py (issue #68).
#
# The guided, offline install: the image's own setup command, installer and
# repository, with the guest's network off. That is what a person installs
# from, and the result does not depend on a mirror answering.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
pacman -S --noconfirm --needed qemu-img swtpm imagemagick
isos=("$root"/build/iso/subarchy-*.iso)
cd "$root"
python3 tools/iso/install-test.py --guided --offline "${isos[0]}"
