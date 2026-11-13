#!/usr/bin/env bash
# The interactive shell setup (ADR 0041): default/shell/zshrc and bashrc
# start without an error in a fresh home, define the aliases and functions,
# and point starship at Subarchy's prompt until the user has their own.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
fail() { echo "shell-rc-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# zsh's compinit refuses group-writable directories on fpath, as a shared
# checkout's are; an installed system's /usr/share is 0755. Test a copy.
shelldir=$work/default-shell
cp -r "$root/default/shell" "$shelldir"
chmod -R go-w "$shelldir"

check() { # shell, rc file
  local shell=$1 rc=$2 home=$work/$1 out
  mkdir -p "$home"
  printf 'source %q\n' "$shelldir/$rc" >"$home/.$rc"
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
    [[ $out == *"starship=$shelldir/starship.toml"* ]] || fail "$shell: starship not pointed at the default prompt: $out"
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

# The subcult command completes its groups and actions from the programs
# on PATH, and `subcult shell set` changes the login shell through chsh.
completion() {
  local bin=$work/bin out
  mkdir -p "$bin"
  # A stand-in dispatcher printing an inventory in the real one's layout:
  # a script command per program, and a compiled command with two actions
  # that have no program of their own.
  cat >"$bin/subcult" <<'STUB'
#!/bin/sh
[ "$1" = commands ] || exit 0
printf '  %-30s  %-20s  %s\n' "subcult app install" "<id>..." "Install apps" "subcult app list" "[--json]" "List apps" \
  "subcult system reboot" "" "Restart" "subcult system shutdown" "" "Turn off" "subcult theme reload" "" "Reload"
STUB
  chmod +x "$bin/subcult"
  # shellcheck disable=SC2016  # runs in the shell under test
  out=$(env -i HOME="$work/bash" PATH="$bin:$PATH" TERM=xterm-256color bash -ic '
    COMP_WORDS=(subcult ""); COMP_CWORD=1; _subcult; echo "first=${COMPREPLY[*]}"
    COMP_WORDS=(subcult system ""); COMP_CWORD=2; _subcult; echo "second=${COMPREPLY[*]}"
    COMP_WORDS=(subcult system re); COMP_CWORD=2; _subcult; echo "third=${COMPREPLY[*]}"
    COMP_WORDS=(subcult app ""); COMP_CWORD=2; _subcult; echo "compiled=${COMPREPLY[*]}"' 2>/dev/null)
  [[ $out == *"first=app commands help system theme"* ]] || fail "bash completion, first word: $out"
  [[ $out == *"second=reboot shutdown"* && $out == *"third=reboot"* ]] || fail "bash completion, actions: $out"
  [[ $out == *"compiled=install list"* ]] || fail "bash completion misses a compiled command's actions: $out"
  if command -v zsh >/dev/null; then
    # shellcheck disable=SC2016
    out=$(cd "$work/zsh" && env -i HOME="$work/zsh" PATH="$bin:$PATH" TERM=xterm-256color ZDOTDIR="$work/zsh" \
      zsh -ic 'echo "zsh=${_comps[subcult]} ${_comps[sub]}"' 2>/dev/null)
    [[ $out == *"zsh=_subcult _subcult"* ]] || fail "zsh does not complete subcult with _subcult: $out"
  fi
  # The real dispatcher's listing has the layout the completions read.
  if [[ -x $root/build/subcult ]]; then
    out=$(PATH="$root/build:$root/bin:$PATH" "$root/build/subcult" commands | awk -F'  +' 'NF > 1 { print $2 }')
    [[ $out == *"subcult system reboot"* ]] || fail "the dispatcher's listing no longer parses into routes: ${out:0:200}"
  fi
}

shell_set() { # the shell to switch to: one that is not the login shell now
  local to=$1 home=$work/set out
  mkdir -p "$home"
  printf '#!/bin/sh\necho "chsh $*" >>"%s/chsh.log"\n' "$home" >"$home/chsh" && chmod +x "$home/chsh"
  out=$(HOME="$home" SUBCULT_TEST_CHSH="$home/chsh" "$root/bin/subcult-shell-set" "$to" 2>&1) || fail "subcult shell set $to: $out"
  [[ $(cat "$home/chsh.log") == "chsh -s /usr/bin/$to" ]] || fail "chsh was not asked for $to: $(cat "$home/chsh.log" 2>&1)"
  grep -q "source /usr/share/subcult/default/shell/${to}rc" "$home/.${to}rc" || fail "the user's ${to}rc does not source the setup"
  HOME="$home" SUBCULT_TEST_CHSH="$home/chsh" "$root/bin/subcult-shell-set" "$to" >/dev/null
  [[ $(grep -c "default/shell/${to}rc" "$home/.${to}rc") == 1 ]] || fail "the source line was added twice"
  if HOME="$home" SUBCULT_TEST_CHSH="$home/chsh" "$root/bin/subcult-shell-set" fish >/dev/null 2>&1; then fail "fish was accepted"; fi
}

ran=0
if command -v zsh >/dev/null; then check zsh zshrc; functions zsh zshrc; ran=$((ran + 1)); fi
check bash bashrc; functions bash bashrc; ran=$((ran + 1))
if command -v starship >/dev/null; then
  STARSHIP_CONFIG=$root/default/shell/starship.toml starship print-config >/dev/null 2>"$work/starship.err" ||
    fail "starship rejects the default prompt: $(cat "$work/starship.err")"
  if grep -qi 'warn\|error' "$work/starship.err"; then fail "starship warns about the default prompt: $(cat "$work/starship.err")"; fi
fi
completion
other=bash
[[ $(getent passwd "$(id -un)" | cut -d: -f7) == */bash ]] && other=zsh
if [[ -x /usr/bin/$other ]]; then shell_set "$other"; fi
echo "shell-rc-test: ok ($ran shells)"
