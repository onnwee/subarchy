#!/usr/bin/env bash
# Exercise the real QML transport with failed, malformed and retired workers.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
if ! command -v quickshell >/dev/null; then
  [[ -z ${CI:-} ]] || { echo 'lock-pam-test: quickshell missing' >&2; exit 1; }
  echo 'lock-pam-test: quickshell missing, skipped'
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -m 700 "$work/run"
cp "$root/lock/PamSession.qml" "$work/"
cp "$root/tools/test/lock-pam.qml" "$work/shell.qml"
cat >"$work/helper" <<'PY'
#!/usr/bin/python3
import json, os, signal, sys, time
case = sys.argv[1]
def send(**frame): print(json.dumps(frame), flush=True)
if case == "bad":
    print("invalid json", flush=True)
elif case == "ask":
    send(event="message", style=1, text="Password:")
    frame = json.loads(sys.stdin.readline())
    send(event="result", result=0 if frame == {"response": 'dummy-password-é\nquoted "text"'} else 1)
elif case == "cancel":
    send(event="message", style=4, text="waiting")
    time.sleep(30)
elif case != "empty":
    send(event="result", result=1 if case == "deny" else 0)
    if case == "duplicate": send(event="result", result=0)
    if case == "broken": sys.exit(4)
    if case == "crashed": os.kill(os.getpid(), signal.SIGKILL)
PY
chmod +x "$work/helper"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$work/run"
for mode in normal missing; do
  export SUBCULT_LOCK_PAM_HELPER="$work/helper" PAM_TEST_MISSING=0
  if [[ $mode == missing ]]; then SUBCULT_LOCK_PAM_HELPER="$work/absent"; PAM_TEST_MISSING=1; fi
  status=0
  quickshell -n -p "$work" >"$work/log" 2>&1 || status=$?
  if ((status)) || ! grep -q 'PASS: lock PAM worker lifecycle' "$work/log"; then cat "$work/log"; exit 1; fi
  if grep -Eq 'dummy-password|FAIL:|ReferenceError|TypeError|Unable to assign|Cannot assign|Failed to load configuration' "$work/log"; then cat "$work/log"; exit 1; fi
done
echo 'lock-pam-test: PASS (success, refusal, malformed/missing/crashed workers, UTF-8 responses and immediate restart after cancellation)'
