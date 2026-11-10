#!/usr/bin/env bash
# Run as root in a disposable Arch CI container: point pacman at Subarchy's
# Arch snapshot (default/pacman/snapshot) and bring every installed package
# to its version there.
#
# The container is newer than the snapshot: its image, and the workflow's
# first `pacman -Syu`, which installs what actions/checkout needs before the
# snapshot date can be read from the checkout. Going back can meet a package
# the snapshot does not have yet. On November 10, 2026 Arch moved to OpenSSL
# 4 and added `openssl-3`, which owns libcrypto.so.3 and libssl.so.3; the
# snapshot's `openssl` 3.6.5 owns the same files, and the downgrade stopped
# on "conflicting files". So the downgrade may overwrite files, and packages
# the snapshot does not know are then dropped from pacman's records (their
# shared files now belong to the snapshot's packages; this container is
# thrown away after the job).
set -euo pipefail

root=$(git rev-parse --show-toplevel)
snapshot=$(cat "$root/default/pacman/snapshot")
[[ $snapshot =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || { echo "pin-snapshot: invalid snapshot date" >&2; exit 1; }
# Pacman expands its own repository and architecture placeholders.
# shellcheck disable=SC2016
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$snapshot" >/etc/pacman.d/mirrorlist
# The archive stalls single connections for longer than pacman's ten-second
# low-speed limit when hundreds of files are fetched; waiting gets them all.
grep -q '^DisableDownloadTimeout' /etc/pacman.conf || sed -i '/^\[options\]/a DisableDownloadTimeout' /etc/pacman.conf
pacman -Syyuu --noconfirm --overwrite '*'
mapfile -t unknown < <(pacman -Qmq || true)
if ((${#unknown[@]})); then
  echo "pin-snapshot: not in the snapshot, dropped from pacman's records: ${unknown[*]}"
  pacman -Rdd --dbonly --noconfirm "${unknown[@]}"
fi
