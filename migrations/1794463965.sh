#!/usr/bin/env bash
# The interactive shell setup (ADR 0041) is new: starship, atuin, zoxide,
# fzf and the aliases start from /usr/share/subcult/default/shell, which
# the user's ~/.zshrc and ~/.bashrc source. New installs get those lines
# from the installer. An install from before had an empty ~/.zshrc, which
# this fills; a ~/.zshrc with the user's own lines is left alone, and so
# is a ~/.bashrc that already has the line.
zshrc=$HOME/.zshrc
if [[ ! -s $zshrc ]]; then
  printf '%s\n' '# Subarchy shell setup (ADR 0041). Your own lines go below.' \
    'source /usr/share/subcult/default/shell/zshrc' >"$zshrc"
fi
bashrc=$HOME/.bashrc
if [[ -f $bashrc ]] && ! grep -q '/usr/share/subcult/default/shell/bashrc' "$bashrc"; then
  printf '\n%s\n%s\n' '# Subarchy shell setup (ADR 0041).' \
    '[[ -r /usr/share/subcult/default/shell/bashrc ]] && source /usr/share/subcult/default/shell/bashrc' >>"$bashrc"
fi
