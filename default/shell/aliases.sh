# shellcheck shell=bash
# Subarchy's shell aliases (ADR 0041), sourced by zsh and bash: keep the
# syntax POSIX. The set follows Omarchy's default/bash/aliases (MIT,
# (c) David Heinemeier Hansson). A tool that is not installed gets no alias.

# Files
if command -v eza >/dev/null 2>&1; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi
if command -v fzf >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
  alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
fi

# Directories
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
# cd that also takes part of a directory's name (zoxide); see functions.sh.
command -v zoxide >/dev/null 2>&1 && alias cd='zd'

# Tools
alias t='tmux attach || tmux new -s Work'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'

# Git
alias g='git'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'
