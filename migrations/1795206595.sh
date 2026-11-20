#!/usr/bin/env bash
# The [multilib] repository stays enabled (ADR 0006): Steam, Wine and Lutris
# need its 32-bit libraries, and `subcult app install steam` failed without
# it. `subcult channel set` now enables it and points it at the channel's
# mirrorlist like core and extra, so new installs have it. This sets the
# current channel again on an install from before; it also moves a
# [multilib] enabled by hand off Arch's live mirrorlist. If multilib's
# database is missing it then syncs: a full -Syu, not -Sy, so it never
# leaves a partial upgrade (`subcult update` has just upgraded, so it only
# fetches the new database). A system on no channel is left alone.
# SUBCULT_TEST_ROOT: a stand-in filesystem root for tools/test/migration-multilib-test.sh.
root=${SUBCULT_TEST_ROOT:-}
channel=$(subcult-channel)
channel=${channel%% *}
case $channel in
  stable | edge) ;;
  *) exit 0 ;;
esac
sudo subcult-channel set "$channel" --quiet
[[ -e $root/var/lib/pacman/sync/multilib.db ]] && exit 0
echo "Enabled the multilib repository (32-bit libraries for Steam, Wine and Lutris); syncing its database"
sudo pacman -Syu --noconfirm ||
  { echo "the multilib database was not synced: run subcult update again" >&2; exit 1; }
