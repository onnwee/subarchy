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
  # ff: pick a file with a preview; eff: open the pick in the editor.
  alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
  alias eff='$EDITOR "$(ff)"'
fi
alias decompress='tar -xzf'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'

# Directories
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
# cd that also takes part of a directory's name (zoxide); see functions.sh.
command -v zoxide >/dev/null 2>&1 && alias cd='zd'

# Tools
alias t='tmux attach || tmux new -s Work'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'
# lazydocker reaches Docker through polkit unless the user has sudoless Docker (ADR 0055).
command -v lazydocker >/dev/null 2>&1 && alias lzd='subcult-docker-tui'
command -v docker >/dev/null 2>&1 && alias d='docker'
command -v mise >/dev/null 2>&1 && alias mup='mise up'

# Coding agents
command -v opencode >/dev/null 2>&1 && alias c='opencode'
command -v claude >/dev/null 2>&1 && alias cx='claude'
command -v codex >/dev/null 2>&1 && alias cy='codex'

# Git
alias g='git'
alias gst='git status -sb'
alias gdf='git diff'
alias glog='git log --oneline --graph --decorate -20'
alias gco='git checkout'
alias gsw='git switch'
alias gpl='git pull'
alias gps='git push'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'
