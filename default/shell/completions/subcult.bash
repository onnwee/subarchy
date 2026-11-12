# shellcheck shell=bash
# bash completion for Subarchy's command line (ADR 0041, ADR 0046). The
# words come from the dispatcher's own inventory (`subcult commands`), so
# they include the actions compiled commands declare (`subcult app
# install`) as well as the subcult-<group>-<action> programs.
_subcult() {
  local cur=${COMP_WORDS[COMP_CWORD]} prefix=subcult route rest i
  local -a next=()
  # One inventory per shell session: reading it starts every compiled command.
  if [[ -z ${_subcult_routes+set} ]]; then
    _subcult_routes=$(command subcult commands 2>/dev/null | awk -F'  +' 'NF > 1 { print $2 }')
  fi
  for ((i = 1; i < COMP_CWORD; i++)); do
    prefix+=" ${COMP_WORDS[i]}"
  done
  while read -r route; do
    [[ $route == "$prefix "* ]] || continue
    rest=${route#"$prefix "}
    next+=("${rest%% *}")
  done <<<"$_subcult_routes"
  ((COMP_CWORD == 1)) && next+=(commands help)
  if ((${#next[@]})); then
    mapfile -t COMPREPLY < <(compgen -W "${next[*]}" -- "$cur" | sort -u)
  else
    mapfile -t COMPREPLY < <(compgen -f -- "$cur")
  fi
}
complete -F _subcult subcult sub
