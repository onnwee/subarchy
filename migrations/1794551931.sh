#!/usr/bin/env bash
# Taildrop (ADR 0058): files sent to this machine land in ~/Downloads.
# tailscaled hands them only to root, so a system unit receives them for
# this user. New installs enable subcult-taildrop@<user> from the
# installer; this does the same for an install from before and starts it
# when tailscaled is running (otherwise the next boot that starts tailscaled
# does). Plain sudo, like the other migrations; if sudo is refused the
# migration stays pending.
unit=$(systemd-escape --template=subcult-taildrop@.service "$USER")
need_sudo() { echo "Taildrop receiving needs sudo: run subcult update migrate again" >&2; exit 1; }
command -v tailscale >/dev/null || exit 0
if ! systemctl is-enabled --quiet "$unit" 2>/dev/null; then
  echo "Saving files sent with Taildrop to ~/Downloads"
  sudo systemctl enable --quiet "$unit" || need_sudo
fi
if systemctl is-active --quiet tailscaled.service; then
  sudo systemctl start "$unit" || need_sudo
fi
