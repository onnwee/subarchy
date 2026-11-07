#!/usr/bin/env bash
# Builds the Subarchy cursor from the default palette and checks the result:
# every name resolves, both formats exist, the arrow is lavender, and a bad
# role is refused without touching the user's settings.
# Usage: tools/test/cursor-test.sh path/to/subcult-cursor
set -euo pipefail

bin=${1:?path to the subcult-cursor binary}
root=$(git rev-parse --show-toplevel)
fail() { echo "cursor-test: $*" >&2; exit 1; }

for tool in rsvg-convert xcursorgen hyprcursor-util python3; do
  command -v "$tool" >/dev/null || { echo "cursor-test: $tool not installed, skipped"; exit 0; }
done

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
out="$work/subcult-cursor"

"$bin" build --role lavender --palette "$root/default/theme/palette.json" \
  --src "$root/default/cursor" --out "$out" >"$work/build.log" 2>&1 ||
  { tail -20 "$work/build.log" >&2; fail "build failed"; }

# The temporary folder may be on another filesystem than the theme (tmpfs
# /tmp against /home); a build must still land.
if [[ -d /dev/shm && -w /dev/shm ]]; then
  shm=$(mktemp -d -p /dev/shm)
  TMPDIR=$shm "$bin" build --role lavender --palette "$root/default/theme/palette.json" \
    --src "$root/default/cursor" --out "$work/xdev/subcult-cursor" >"$work/xdev.log" 2>&1 ||
    { rm -rf -- "$shm"; tail -5 "$work/xdev.log" >&2; fail "build across filesystems failed"; }
  rm -rf -- "$shm"
  [[ -f $work/xdev/subcult-cursor/hyprcursors/default.hlc ]] || fail "cross-filesystem build incomplete"
  leftovers=$(find "$work/xdev" -mindepth 1 -maxdepth 1 ! -name subcult-cursor)
  [[ -z $leftovers ]] || fail "build left behind: $leftovers"
fi

for name in left_ptr text pointer; do
  [[ $(head -c4 "$out/cursors/$name") == Xcur ]] || fail "cursors/$name is not an Xcursor file"
done

while IFS=$'\t' read -r shape _ _ names; do
  [[ -z $shape || $shape == \#* ]] && continue
  for name in $shape $names; do
    [[ -e $out/cursors/$name ]] || fail "cursor name $name does not resolve"
  done
  [[ -f $out/hyprcursors/$shape.hlc ]] || fail "no hyprcursor for $shape"
done <"$root/default/cursor/shapes.tsv"

grep -qx 'Name=subcult-cursor' "$out/index.theme" || fail "index.theme lacks Name"
[[ -f $out/manifest.hl ]] || fail "no hyprcursor manifest"

# Most common opaque colour of the 24 px arrow, read from the Xcursor file.
colour=$(python3 - "$out/cursors/left_ptr" <<'EOF'
import collections, struct, sys
data = open(sys.argv[1], "rb").read()
_, hsize, _, ntoc = struct.unpack_from("<4sIII", data, 0)
counts = collections.Counter()
for i in range(ntoc):
    ctype, subtype, pos = struct.unpack_from("<III", data, hsize + i * 12)
    if ctype != 0xFFFD0002 or subtype != 24:
        continue
    width, height = struct.unpack_from("<II", data, pos + 16)
    pixels = struct.unpack_from(f"<{width * height}I", data, pos + 36)
    for p in pixels:
        if p >> 24 == 0xFF:
            counts[p & 0xFFFFFF] += 1
    break
print("#%06X" % counts.most_common(1)[0][0] if counts else "none")
EOF
)
[[ $colour == "#A78BFA" ]] || fail "24 px arrow is mostly $colour, want #A78BFA"

# A role the palette does not have is refused and the settings stay as they were.
home="$work/home"
mkdir -p "$home/.config/subcult"
printf '{"role": "mauve", "size": 32}\n' >"$home/.config/subcult/cursor.json"
before=$(cat "$home/.config/subcult/cursor.json")
set +e
HOME=$home "$bin" set --role nonsense --palette "$root/default/theme/palette.json" >/dev/null 2>&1
status=$?
set -e
[[ $status == 2 ]] || fail "set --role nonsense exited $status, want 2"
[[ $(cat "$home/.config/subcult/cursor.json") == "$before" ]] || fail "cursor.json changed after a refused set"

# A size chosen with set survives a new session: Hyprland reads it from
# ~/.config/subcult/cursor-env.lua at login. GSettings uses a throwaway
# backend so the test cannot touch the real desktop settings.
home2="$work/home2"
mkdir -p "$home2"
env -u DBUS_SESSION_BUS_ADDRESS -u HYPRLAND_INSTANCE_SIGNATURE GSETTINGS_BACKEND=memory HOME="$home2" SUBCULT_PATH="$root" \
  "$bin" set --size 32 --src "$root/default/cursor" >"$work/set.log" 2>&1 ||
  { tail -5 "$work/set.log" >&2; fail "set --size 32 failed"; }
grep -q '"HYPRCURSOR_SIZE", "32"' "$home2/.config/subcult/cursor-env.lua" 2>/dev/null ||
  fail "set --size does not persist the size for the next session"
grep -q '"XCURSOR_SIZE", "32"' "$home2/.config/subcult/cursor-env.lua" || fail "XCURSOR_SIZE not persisted"

echo "cursor-test: ok"
