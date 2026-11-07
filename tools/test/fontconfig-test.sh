#!/usr/bin/env bash
# Checks the font role rules against this machine's fontconfig set-up: the
# generic names resolve to the role fonts, a user file overrides a role,
# and families that apps ask for by name keep resolving as they do without
# Subarchy's rules (documents keep their fonts).
set -euo pipefail

root=$(git rev-parse --show-toplevel)
conf="$root/default/fontconfig/44-subarchy-roles.conf"
fail() { echo "fontconfig-test: $*" >&2; exit 1; }

for f in /etc/fonts/fonts.conf "$conf"; do
  [[ -f $f ]] || fail "missing $f"
done
families=$(fc-list : family)
if ! grep -q '^JetBrainsMono Nerd Font' <<<"$families" || ! grep -q '^Liberation Mono' <<<"$families"; then
  echo "fontconfig-test: JetBrainsMono Nerd Font or Liberation Mono not installed, skipped"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Two copies of the system configuration, one with the roles file added.
setup() { # dir with-roles
  mkdir -p "$1/conf.d" "$1/cache" "$1/home/subcult"
  cp /etc/fonts/fonts.conf "$1/fonts.conf"
  for f in /etc/fonts/conf.d/*.conf; do
    [[ $(basename "$f") == *subarchy-roles* ]] && continue
    ln -s "$(readlink -f "$f")" "$1/conf.d/$(basename "$f")"
  done
  [[ $2 == yes ]] && ln -s "$conf" "$1/conf.d/44-subarchy-roles.conf"
  return 0
}
setup "$work/plain" no
setup "$work/roles" yes

match() { # dir pattern
  FONTCONFIG_PATH=$1 FONTCONFIG_FILE=$1/fonts.conf XDG_CONFIG_HOME=$1/home XDG_CACHE_HOME=$1/cache \
    fc-match -f '%{family[0]}' "$2"
}

[[ $(match "$work/roles" monospace) == "JetBrainsMono Nerd Font" ]] ||
  fail "monospace resolves to $(match "$work/roles" monospace)"

for family in "DejaVu Sans" "DejaVu Sans Mono" "Arial" "Times New Roman" "Liberation Serif" "Courier New"; do
  want=$(match "$work/plain" "$family")
  got=$(match "$work/roles" "$family")
  [[ $got == "$want" ]] || fail "$family resolves to $got with the roles, $want without"
done

cat >"$work/roles/home/subcult/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test qual="any" name="family"><string>monospace</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Liberation Mono</string></edit>
  </match>
</fontconfig>
EOF
[[ $(match "$work/roles" monospace) == "Liberation Mono" ]] ||
  fail "the user's file does not override monospace ($(match "$work/roles" monospace))"
[[ $(match "$work/roles" Arial) == "$(match "$work/plain" Arial)" ]] ||
  fail "the user's file changes a named family"

echo "fontconfig-test: ok"
