#!/usr/bin/env bash
# Gitea's Arch registry resolves file names by substring. Check every
# recipe's real makepkg output, including split packages, before building.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
files=()
for dir in "$root"/packaging/*/ "$root"/packaging/aur/*/; do
  [[ -f $dir/PKGBUILD ]] || continue
  list=$(cd "$dir" && makepkg --packagelist)
  [[ -n $list ]] || { echo "check-package-names: empty package list for $dir" >&2; exit 1; }
  while IFS= read -r path; do
    files+=("${path##*/}")
  done <<<"$list"
done
((${#files[@]})) || { echo 'check-package-names: no package files' >&2; exit 1; }
python3 "$root/tools/ci/publish-packages.py" --check-names "${files[@]}"
