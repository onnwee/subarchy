#!/usr/bin/env bash
# lsusb (usbutils), inotifywait (inotify-tools, for limine-snapper-sync's
# watcher) and rtkit (realtime scheduling for PipeWire) were in no install
# list (#198). New installs get them from install/packages; this installs the
# missing ones on an install from before. `subcult update` has synced the
# package databases by the time this runs. Plain sudo, like the other
# migrations; if sudo or pacman fails the migration stays pending.
# pacman -T prints the missing packages, one per line, and exits 0 if none are.
missing=$(pacman -T usbutils inotify-tools rtkit) && exit 0
missing=${missing//$'\n'/ }
echo "Installing $missing"
# shellcheck disable=SC2086 # one package per word
sudo pacman -S --needed --noconfirm $missing ||
  { echo "$missing not installed: run subcult update migrate again" >&2; exit 1; }
