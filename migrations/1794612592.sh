#!/usr/bin/env bash
# The weather widget and panel call linecast for the forecast, sun, moon,
# tides and place search. Subarchy's repository built it, but no install
# list named it, so an earlier install has no forecast ("linecast gave no
# forecast") and cannot search for a place. New installs get it from
# install/packages/desktop.txt; this installs it on an install from before.
# `subcult update` has synced the package databases by the time this runs.
# Plain sudo, like the other migrations; if sudo or pacman fails the
# migration stays pending.
command -v linecast >/dev/null && exit 0
echo "Installing linecast for the weather forecast and place search"
sudo pacman -S --needed --noconfirm linecast ||
  { echo "linecast was not installed: run subcult update migrate again" >&2; exit 1; }
