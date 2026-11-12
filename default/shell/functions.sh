# shellcheck shell=bash
# Subarchy's shell functions (ADR 0041), sourced by zsh and bash: only
# syntax both accept.

# n: Neovim on the arguments, or on the current folder.
n() {
  if [ "$#" -eq 0 ]; then command nvim .; else command nvim "$@"; fi
}

# open FILE...: with the desktop's default app, without tying up the shell.
open() (
  xdg-open "$@" >/dev/null 2>&1 &
)

# zd: cd, falling back to zoxide's best match for a folder that is not
# here. `cd` is aliased to it when zoxide is installed.
zd() {
  if [ "$#" -eq 0 ]; then
    builtin cd ~ || return
  elif [ -d "$1" ] || [ "$1" = - ]; then
    builtin cd "$1" || return
  elif ! z "$@"; then
    echo "cd: no such directory: $*" >&2
    return 1
  fi
}
