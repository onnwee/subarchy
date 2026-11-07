#!/usr/bin/env bash
# End-to-end check of the subcult dispatcher binary against fixture commands.
set -euo pipefail

bin=$(realpath "${1:?usage: dispatcher-smoke.sh path/to/subcult}")
dir=$(mktemp -d)
cleanup() { rm -r -- "$dir"; }
trap cleanup EXIT

cat >"$dir/subcult-echo-args" <<'SCRIPT'
#!/usr/bin/env bash
# subcult:summary=Print the arguments it was given
printf '%s\n' "$0" "$@"
SCRIPT
chmod +x "$dir/subcult-echo-args"
ln -s "$bin" "$dir/sub"

export PATH="$dir:$PATH"
fail() { echo "smoke: $*" >&2; exit 1; }

out=$("$bin" echo args one "two words")
[[ $out == *"subcult-echo-args"* && $out == *"two words"* ]] || fail "exec routing: $out"

out=$(sub echo args x)
[[ $out == *x ]] || fail "sub alias: $out"

"$bin" commands --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] and any(c["binary"]=="subcult-echo-args" for c in d["commands"])' \
  || fail "commands --json"

set +e
"$bin" nonexistent-command >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 127 ]] || fail "unknown command exit $code"

echo "smoke: ok"
