#!/usr/bin/env bash
# The interactive shell setup (ADR 0041): default/shell/zshrc and bashrc
# start without an error in a fresh home, define the aliases and functions,
# and point starship at Subarchy's prompt until the user has their own.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
fail() { echo "shell-rc-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

check() { # shell, rc file
  local shell=$1 rc=$2 home=$work/$1 out
  mkdir -p "$home"
  printf 'source %q\n' "$root/default/shell/$rc" >"$home/.$rc"
  # shellcheck disable=SC2016  # the commands run in the shell under test
  out=$(cd "$home" && env -i HOME="$home" PATH="$PATH" TERM=xterm-256color ZDOTDIR="$home" \
    "$shell" -ic 'alias g; alias gcm; type n | head -1; type zd | head -1; echo "editor=$EDITOR"; echo "starship=${STARSHIP_CONFIG:-}"' 2>"$home/err") ||
    fail "$shell exited with an error: $(cat "$home/err")"
  # Either shell may note that it has no terminal for job control; nothing else.
  if grep -v -e 'no job control' -e 'cannot set terminal process group' -e "can't set option: zle" -e '^$' "$home/err" | grep -q .; then
    fail "$shell wrote to stderr: $(cat "$home/err")"
  fi
  [[ $out == *"git"* && $out == *"git commit -m"* ]] || fail "$shell: git aliases missing: $out"
  [[ $out == *"n is a"* && $out == *"zd is a"* ]] || fail "$shell: functions missing: $out"
  [[ $out == *"editor=nvim"* ]] || fail "$shell: EDITOR not set: $out"
  if command -v starship >/dev/null; then
    [[ $out == *"starship=$root/default/shell/starship.toml"* ]] || fail "$shell: starship not pointed at the default prompt: $out"
    # The user's own prompt wins.
    mkdir -p "$home/.config" && : >"$home/.config/starship.toml"
    # shellcheck disable=SC2016
    out=$(cd "$home" && env -i HOME="$home" PATH="$PATH" TERM=xterm-256color ZDOTDIR="$home" "$shell" -ic 'echo "starship=${STARSHIP_CONFIG:-}"' 2>/dev/null)
    [[ $out == *"starship="$'\n'* || $out == "starship=" || $out == *"starship=" ]] || fail "$shell: the user's starship.toml was overridden: $out"
  fi
}

# The functions do what they say in both shells: a worktree made and
# removed, an archive made and unpacked, usage and refusals.
functions() { # shell, rc file
  local shell=$1 rc=$2 home=$work/$1 out
  mkdir -p "$home/repo" "$home/pack/dir"
  echo hello >"$home/pack/dir/file"
  git -C "$home/repo" init -q -b main
  git -C "$home/repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m first
  # shellcheck disable=SC2016  # the commands run in the shell under test
  out=$(cd "$home" && env -i HOME="$home" PATH="$PATH" TERM=xterm-256color ZDOTDIR="$home" TMUX= "$shell" -ic '
    ga; echo "ga-usage=$?"
    tdl c; echo "tdl-outside=$?"
    tsl 2; echo "tsl-usage=$?"
    fip onlyhost; echo "fip-usage=$?"
    cd pack && compress dir && rm -r dir && decompress dir.tar.gz && cat dir/file && cd ..
    cd repo && ga topic && echo "in=$(basename "$PWD") branch=$(git branch --show-current)"
    gd <<<n; echo "gd-no=$? still=$(basename "$PWD")"
    gd <<<y >/dev/null; echo "gd-yes=$? back=$(basename "$PWD") left=$(git branch --list topic | wc -l)"
    gd </dev/null; echo "gd-not-worktree=$?"
    alias gst lzd eff 2>/dev/null | wc -l
  ' 2>/dev/null) || fail "$shell: the function checks exited with an error: $out"
  for want in "ga-usage=1" "tdl-outside=1" "tsl-usage=1" "fip-usage=1" "hello" "in=repo--topic branch=topic" \
    "gd-no=1 still=repo--topic" "gd-yes=0 back=repo left=0" "gd-not-worktree=1"; do
    [[ $out == *"$want"* ]] || fail "$shell: expected '$want' in: $out"
  done
  [[ ! -e $home/repo--topic ]] || fail "$shell: gd left the worktree folder"
}

ran=0
if command -v zsh >/dev/null; then check zsh zshrc; functions zsh zshrc; ran=$((ran + 1)); fi
check bash bashrc; functions bash bashrc; ran=$((ran + 1))
if command -v starship >/dev/null; then
  STARSHIP_CONFIG=$root/default/shell/starship.toml starship print-config >/dev/null 2>"$work/starship.err" ||
    fail "starship rejects the default prompt: $(cat "$work/starship.err")"
  if grep -qi 'warn\|error' "$work/starship.err"; then fail "starship warns about the default prompt: $(cat "$work/starship.err")"; fi
fi
echo "shell-rc-test: ok ($ran shells)"
