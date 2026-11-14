#!/usr/bin/env bash
# `hostname` comes from inetutils, which no install list named, so an
# earlier install has no `hostname` command. New installs get it from
# install/packages/base.txt; this installs it on an install from before.
# `subcult update` has synced the package databases by the time this runs.
# Plain sudo, like the other migrations; if sudo or pacman fails the
# migration stays pending.
command -v hostname >/dev/null && exit 0
echo "Installing inetutils for the hostname command"
sudo pacman -S --needed --noconfirm inetutils ||
  { echo "inetutils was not installed: run subcult update migrate again" >&2; exit 1; }
