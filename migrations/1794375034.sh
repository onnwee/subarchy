#!/usr/bin/env bash
# Pult 0.3.0 can theme Subarchy's own shell, lock and Hyprland colours
# (issue #76). A user who installed with an older Pult has no palette file
# yet: apply their active theme once more so Pult writes it. Someone who
# removed their theme with `pult uninstall` has none, and is left alone.
command -v pult >/dev/null || exit 0
[[ ! -e ${XDG_CONFIG_HOME:-$HOME/.config}/subcult/theme/palette.json ]] || exit 0
theme=$(pult doctor 2>/dev/null | sed -n 's/^Active theme: \([^;]*\);.*/\1/p')
case $theme in
  "" | none) exit 0 ;;
  # The default theme is a file beside its profile, not a catalog entry.
  subcult-minimal) pult apply -yes -profile /usr/share/subcult/default/theme/subarchy.toml ;;
  *) pult apply -yes "$theme" ;;
esac
