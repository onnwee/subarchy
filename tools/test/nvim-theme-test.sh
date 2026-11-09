#!/usr/bin/env bash
# The subcult colour scheme (ADR 0045): with a user palette it maps the
# roles (Normal is text on base); without any palette it falls back to
# Subcult Ink. Runs Neovim headless with the repository's colors on the
# runtime path.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "nvim-theme-test: $*" >&2; exit 1; }
command -v nvim >/dev/null || { echo "nvim-theme-test: nvim not installed, skipped"; exit 0; }

home=$(mktemp -d)
trap 'rm -rf -- "$home"' EXIT
mkdir -p "$home/.config/subcult/theme"

run() { # prints "<scheme> <Normal fg> <Normal bg>"
  HOME=$home XDG_CONFIG_HOME=$home/.config SUBCULT_PATH=$home/none nvim --headless --clean -u NONE \
    "+set runtimepath+=$root/default/nvim" "+colorscheme subcult" \
    '+lua local n = vim.api.nvim_get_hl(0, { name = "Normal" }); print(vim.g.colors_name .. " " .. string.format("%06X %06X", n.fg or 0, n.bg or 0))' +qa 2>&1 | tail -1
}

# No palette anywhere: Subcult Ink's colours under the subcult name.
[[ $(run) == "subcult F0ECE4 100B19" ]] || fail "fallback: $(run)"

# A user palette: its roles.
printf '{"schema": 1, "colors": {"base": "#112233", "text": "#EEDDCC", "mauve": "#AA55FF", "surface0": "#223344"}}\n' >"$home/.config/subcult/theme/palette.json"
[[ $(run) == "subcult EEDDCC 112233" ]] || fail "user palette: $(run)"

# A broken palette file falls back.
printf '{ broken' >"$home/.config/subcult/theme/palette.json"
[[ $(run) == "subcult F0ECE4 100B19" ]] || fail "broken palette: $(run)"

echo "nvim-theme-test: ok"
