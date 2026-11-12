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

# y: yazi, leaving the shell in the folder yazi was in when it closed.
y() {
  local tmp cwd
  tmp=$(mktemp -t yazi-cwd.XXXXXX) || return
  command yazi "$@" --cwd-file="$tmp"
  cwd=$(cat -- "$tmp" 2>/dev/null)
  rm -f -- "$tmp"
  if [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then builtin cd -- "$cwd" || return; fi
}

# compress DIR: DIR.tar.gz beside it. `decompress` is the alias back.
compress() {
  tar -czf "${1%/}.tar.gz" "${1%/}"
}

# sff DEST: pick a file (newest first) and scp it to DEST, as in
# `sff host:/tmp/`.
sff() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: sff <destination> (e.g. sff host:/tmp/)"
    return 1
  fi
  local file
  file=$(find . -type f -printf '%T@\t%p\n' | sort -rn | cut -f2- |
    fzf --preview 'bat --style=numbers --color=always {}') && [ -n "$file" ] && scp "$file" "$1"
}

# Git worktrees, one folder per branch beside the repository (Omarchy's
# ga and gd). ga BRANCH: a new branch in ../<repo>--<branch>, and go there.
ga() {
  if [ -z "${1:-}" ]; then
    echo "Usage: ga [branch name]"
    return 1
  fi
  local branch=$1 wt_path
  wt_path="../$(basename "$PWD")--$1"
  git worktree add -b "$branch" "$wt_path" || return
  if command -v mise >/dev/null 2>&1; then mise trust "$wt_path" >/dev/null 2>&1; fi
  builtin cd "$wt_path" || return
}

# gd: from inside a worktree made by ga, remove it and its branch.
gd() {
  local cwd worktree root branch reply
  cwd=$(pwd)
  worktree=$(basename "$cwd")
  root=${worktree%%--*}
  branch=${worktree#*--}
  # Only a folder named <repo>--<branch> is a worktree of ga's.
  if [ "$root" = "$worktree" ]; then
    echo "gd: $worktree is not a worktree made by ga"
    return 1
  fi
  printf 'Remove the worktree %s and the branch %s? [y/N] ' "$worktree" "$branch"
  read -r reply
  case $reply in
  y | Y | yes) ;;
  *) return 1 ;;
  esac
  builtin cd "../$root" || return
  git worktree remove "$cwd" --force || return 1
  git branch -D "$branch"
}

# SSH port forwards (Omarchy's fip, dip, lip).
# fip HOST PORT...: forward local ports to the same ports on HOST.
fip() {
  if [ "$#" -lt 2 ]; then
    echo "Usage: fip <host> <port1> [port2] ..."
    return 1
  fi
  local host=$1 port
  shift
  for port in "$@"; do
    ssh -f -N -L "${port}:localhost:${port}" "$host" && echo "Forwarding localhost:$port -> $host:$port"
  done
}

# dip PORT...: stop those forwards.
dip() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: dip <port1> [port2] ..."
    return 1
  fi
  local port
  for port in "$@"; do
    if pkill -f "ssh.*-L ${port}:localhost:${port}"; then
      echo "Stopped forwarding port $port"
    else
      echo "No forwarding on port $port"
    fi
  done
}

# lip: list the forwards.
lip() {
  pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+" || echo "No active forwards"
}

# tmux layouts (Omarchy's tdl, tdlm, tsl), run inside tmux.
# tdl AI [AI2]: the editor on the left, AI (c, cx, cy or any command) on
# the right, a terminal along the bottom.
tdl() {
  if [ -z "${1:-}" ]; then
    echo "Usage: tdl <c|cx|cy|other_ai> [<second_ai>]"
    return 1
  fi
  if [ -z "${TMUX:-}" ]; then
    echo "You must start tmux to use tdl."
    return 1
  fi
  local dir=$PWD editor_pane=$TMUX_PANE ai_pane ai2_pane
  tmux rename-window -t "$editor_pane" "$(basename "$dir")"
  tmux split-window -v -p 15 -t "$editor_pane" -c "$dir"
  ai_pane=$(tmux split-window -h -p 30 -t "$editor_pane" -c "$dir" -P -F '#{pane_id}')
  if [ -n "${2:-}" ]; then
    ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$dir" -P -F '#{pane_id}')
    tmux send-keys -t "$ai2_pane" "$2" C-m
  fi
  tmux send-keys -t "$ai_pane" "$1" C-m
  tmux send-keys -t "$editor_pane" "${EDITOR:-nvim} ." C-m
  tmux select-pane -t "$editor_pane"
}

# tdlm AI [AI2]: a tdl window for every folder in the current one.
tdlm() {
  if [ -z "${1:-}" ]; then
    echo "Usage: tdlm <c|cx|cy|other_ai> [<second_ai>]"
    return 1
  fi
  if [ -z "${TMUX:-}" ]; then
    echo "You must start tmux to use tdlm."
    return 1
  fi
  local base=$PWD first=1 dir pane
  tmux rename-session "$(basename "$base" | tr '.:' '--')"
  for dir in "$base"/*/; do
    [ -d "$dir" ] || continue
    dir=${dir%/}
    if [ "$first" = 1 ]; then
      tmux send-keys -t "$TMUX_PANE" "cd '$dir' && tdl $1 ${2:-}" C-m
      first=0
    else
      pane=$(tmux new-window -c "$dir" -P -F '#{pane_id}')
      tmux send-keys -t "$pane" "tdl $1 ${2:-}" C-m
    fi
  done
}

# tsl COUNT COMMAND: COUNT tiled panes, each running COMMAND.
tsl() {
  if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "Usage: tsl <pane_count> <command>"
    return 1
  fi
  if [ -z "${TMUX:-}" ]; then
    echo "You must start tmux to use tsl."
    return 1
  fi
  local first=$TMUX_PANE last=$TMUX_PANE new i=1
  tmux rename-window -t "$first" "$(basename "$PWD")"
  tmux send-keys -t "$first" "$2" C-m
  while [ "$i" -lt "$1" ]; do
    new=$(tmux split-window -h -t "$last" -c "$PWD" -P -F '#{pane_id}') || return
    tmux select-layout -t "$first" tiled
    tmux send-keys -t "$new" "$2" C-m
    last=$new
    i=$((i + 1))
  done
  tmux select-pane -t "$first"
}
