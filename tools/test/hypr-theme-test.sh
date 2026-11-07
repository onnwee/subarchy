#!/usr/bin/env bash
# A broken user theme file (~/.config/subcult/theme/hyprland.lua, Theme
# Tender's) must not stop the rest of Subarchy's Hyprland defaults loading.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "hypr-theme-test: $*" >&2; exit 1; }
command -v Hyprland >/dev/null || { echo "hypr-theme-test: Hyprland not installed, skipped"; exit 0; }

home=$(mktemp -d)
trap 'rm -rf -- "$home"' EXIT
mkdir -p "$home/.config/subcult/theme" "$home/.config/hypr"
printf 'hl.config({ general = {\n' >"$home/.config/subcult/theme/hyprland.lua"
printf 'hl.env("XCURSOR_SIZE",\n' >"$home/.config/subcult/cursor-env.lua"

out=$(HOME=$home SUBCULT_PATH=$root Hyprland --verify-config -c "$root/default/hypr/user-hyprland.lua" 2>&1) || true
grep -qx 'config ok' <<<"$out" || fail "a broken user theme breaks the config: $(tail -3 <<<"$out")"
echo "hypr-theme-test: ok"
