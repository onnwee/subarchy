#!/usr/bin/env bash
# Taildrop (ADR 0058) with stand-ins for tailscale, setpriv, pkexec,
# notify-send and the file picker.
#
# Receive (/usr/lib/subcult/taildrop-receive, root): files tailscale
# delivers into root's staging folder reach the user's Downloads through
# setpriv as that user, under free names (a taken name gets -1), and each
# is announced (a link to nowhere, a folder or a link to a folder also
# takes a name, and a long name is shortened to fit its number; a file that
# cannot be saved is announced as such); a finished get an earlier run left
# is delivered first, and of an unfinished one the files it logged as
# written arrive while a cut-off file is dropped unannounced; a failed get
# delivers the files it finished; a removed Downloads is made again; a
# refusal (signed out) fails --once.
#
# Send (`subcult tailscale send`): each picked file goes to the root helper
# through pkexec as standard input, with its name and the machine's
# address; a name is looked up first; --name names the machine in the
# picker and the notification; a closed picker sends nothing; a failed
# transfer is announced and fails.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "taildrop-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/home/Downloads" "$work/spool"
chmod 0700 "$work/spool"
export TD_TEST="$work" PATH="$work/bin:$PATH" HOME="$work/home" STATE_DIRECTORY="$work/spool"
unset XDG_DOWNLOAD_DIR

cat >"$work/bin/tailscale" <<'STUB'
#!/bin/bash
echo "$*" >>"$TD_TEST/tailscale-log"
case "$1 $2" in
"file get")
  [[ -e $TD_TEST/signed-out ]] && { echo "getting WaitingFiles: Taildrop disabled; no storage directory" >&2; exit 1; }
  dest=${*: -1}
  # As tailscale: each file is logged once written, before it leaves the
  # inbox; "waiting for file..." has no line end.
  printf 'waiting for file...'
  printf 'new' >"$dest/notes.txt"
  echo "wrote notes.txt as $dest/notes.txt (3 bytes)"
  # Failing halfway: one file written, the next one cut off. On a full
  # disk the receiver's log of the get can lose the record too.
  [[ -e $TD_TEST/log-lost ]] && rm -f -- "$dest.log"
  [[ -e $TD_TEST/get-fails ]] && { printf 'im' >"$dest/photo.png"; echo "failed to write $dest/photo.png: no space left on device" >&2; exit 1; }
  printf 'img' >"$dest/photo.png"
  echo "wrote photo.png as $dest/photo.png (3 bytes)"
  echo "moved 2/2 files";;
"ip -1") [[ $3 == kvant* ]] && echo 100.64.0.2 || { echo "no such peer" >&2; exit 1; };;
esac
exit 0
STUB
# setpriv: the options are recorded, the command after -- runs as is.
cat >"$work/bin/setpriv" <<'STUB'
#!/bin/bash
opts=()
while [[ $1 != -- ]]; do opts+=("$1"); shift; done
shift
echo "${opts[*]}" >>"$TD_TEST/setpriv-log"
exec "$@"
STUB
# pkexec: runs the helper, as the test is not root; the helper's
# tailscale is the stand-in above, which stores what it is given.
cat >"$work/bin/pkexec" <<'STUB'
#!/bin/bash
echo "pkexec $*" >>"$TD_TEST/pkexec-log"
[[ $2 == send ]] || exit 1
[[ -e $TD_TEST/cp-fails ]] && { echo "100.64.0.2: no matching peer" >&2; exit 1; }
cat >>"$TD_TEST/sent"
STUB
cat >"$work/bin/notify-send" <<'STUB'
#!/bin/bash
printf '%s\n' "${*: -2:1} | ${*: -1}" >>"$TD_TEST/notes"
STUB
cat >"$work/chooser" <<'STUB'
#!/bin/bash
echo "$*" >>"$TD_TEST/chooser-log"
[[ -e $TD_TEST/chooser-closed ]] && exit 1
printf '%s\n' "$TD_TEST/a file.pdf" "$TD_TEST/b.txt"
STUB
chmod +x "$work/bin/"* "$work/chooser"
printf 'A' >"$work/a file.pdf"
printf 'B' >"$work/b.txt"

me=$(id -un)
receive() { "$root/tools/tailscale/taildrop-receive.sh" --once "$me"; }
dl=$work/home/Downloads
spool=$work/spool

# A taken name is kept, the new file gets -1; a finished get an earlier run
# left arrives too; of an unfinished one, the file it logged as written
# arrives (tailscaled no longer has it) and the cut-off one is dropped
# without a word.
printf 'old' >"$dl/notes.txt"
mkdir -p "$spool/done.AAAAAA" "$spool/get.BBBBBB"
printf 'left' >"$spool/done.AAAAAA/left.bin"
printf 'whole' >"$spool/get.BBBBBB/whole (1).txt"
printf 'cut' >"$spool/get.BBBBBB/cut-off.iso"
printf 'waiting for file...wrote whole.txt as %s (5 bytes)\n' "$spool/get.BBBBBB/whole (1).txt" >"$spool/get.BBBBBB.log"
receive || fail "receive --once failed"
[[ $(<"$dl/notes.txt") == old && $(<"$dl/notes-1.txt") == new ]] || fail "a taken name was overwritten: $(ls -A "$dl")"
[[ $(<"$dl/photo.png") == img && $(<"$dl/left.bin") == left ]] || fail "files missing from Downloads: $(ls -A "$dl")"
[[ $(<"$dl/whole (1).txt") == whole ]] || fail "a finished file of an unfinished get was lost: $(ls -A "$dl")"
[[ ! -e $dl/cut-off.iso ]] || fail "a file from an unfinished get was delivered"
[[ -z $(ls -A "$spool") ]] || fail "staging not emptied: $(ls -A "$spool")"
[[ -z $(find "$dl" -name '.taildrop-*') ]] || fail "a hidden copy was left: $(ls -A "$dl")"
grep -qE "^file get --wait --verbose --conflict=rename $spool/get\.[A-Za-z0-9]{6}\$" "$work/tailscale-log" ||
  fail "tailscale file get: $(cat "$work/tailscale-log")"
# Each file went over as the user, with the session bus for the notification.
uid=$(id -u) gid=$(id -g)
[[ $(sort -u "$work/setpriv-log") == "--reuid=$uid --regid=$gid --init-groups --reset-env" ]] ||
  fail "not delivered as the user: $(sort -u "$work/setpriv-log")"
[[ $(wc -l <"$work/setpriv-log") == 4 ]] || fail "deliveries: $(wc -l <"$work/setpriv-log")"
[[ $(grep -c '^Received ' "$work/notes") == 4 ]] || fail "not every file announced: $(cat "$work/notes")"
grep -qx 'Received notes-1.txt | Saved to ~/Downloads' "$work/notes" || fail "announcement: $(cat "$work/notes")"
grep -q 'cut-off' "$work/notes" && fail "a file from an unfinished get was announced"

# A get that fails halfway delivers the file it finished (tailscaled has
# dropped it) but not the cut-off one, and leaves nothing behind.
touch "$work/get-fails"
: >"$work/notes"
rm -f "$dl/photo.png"
if receive 2>"$work/err"; then fail "receive --once succeeded after a failed get"; fi
[[ $(<"$work/err") == "taildrop-receive: failed to write $spool/get."??????"/photo.png: no space left on device" ]] ||
  fail "failed get error: $(<"$work/err")"
[[ $(<"$dl/notes-2.txt") == new ]] || fail "a failed get lost its finished file: $(ls -A "$dl")"
[[ ! -e $dl/photo.png ]] || fail "a cut-off file was delivered: $(ls -A "$dl")"
[[ $(cat "$work/notes") == 'Received notes-2.txt | Saved to ~/Downloads' ]] || fail "failed get announcements: $(cat "$work/notes")"
[[ -z $(ls -A "$spool") ]] || fail "a failed get left files: $(ls -A "$spool")"
# The same with the log on disk lost (a full disk): the finished file is
# still delivered, from the record kept in memory.
touch "$work/log-lost"
if receive 2>/dev/null; then fail "receive --once succeeded after a failed get"; fi
rm "$work/get-fails" "$work/log-lost"
[[ $(<"$dl/notes-3.txt") == new ]] || fail "a failed get without its log lost its finished file: $(ls -A "$dl")"
[[ ! -e $dl/photo.png && -z $(ls -A "$spool") ]] || fail "a failed get without its log: $(ls -A "$dl") / $(ls -A "$spool")"

# Downloads removed: the delivery makes it again.
rm -rf "$dl"
receive || fail "receive --once failed after Downloads was removed"
[[ -f $dl/notes.txt ]] || fail "Downloads not made again: $(ls -A "$work/home")"

# Signed out: --once fails, nothing lands.
rm -f "$dl"/*
touch "$work/signed-out"
if receive 2>/dev/null; then fail "receive --once succeeded while signed out"; fi
rm "$work/signed-out"
[[ -z $(ls -A "$dl") ]] || fail "files landed while signed out: $(ls -A "$dl")"

# The user's side refuses a name with a folder in it.
if "$root/tools/tailscale/taildrop-receive.sh" --deliver ../escape </dev/null 2>/dev/null; then fail "--deliver took a name with a folder"; fi
[[ ! -e $work/home/escape ]] || fail "--deliver wrote outside Downloads"

# A link to nowhere takes its name; a long taken name is shortened to fit
# 255 bytes with its number, in whole characters.
deliver() { "$root/tools/tailscale/taildrop-receive.sh" --deliver "$1"; }
ln -s "$work/nowhere" "$dl/dangling.txt"
printf 'd' | deliver dangling.txt || fail "--deliver failed on a name a dangling link takes"
[[ -L $dl/dangling.txt && $(<"$dl/dangling-1.txt") == d ]] || fail "dangling link: $(ls -A "$dl")"
long="$(printf 'é%.0s' {1..125})a.txt"
: >"$dl/$long"
printf 'l' | deliver "$long" || fail "--deliver failed on a long taken name"
short=$(find "$dl" -name '*-1.txt' ! -name 'dangling-1.txt' -printf '%f\n')
[[ $(LC_ALL=C; echo "${#short}") -le 255 && $short == "$(printf 'é%.0s' {1..124})-1.txt" ]] ||
  fail "long name: $short"
iconv -f UTF-8 -t UTF-8 <<<"$short" >/dev/null || fail "a shortened name is not UTF-8: $short"
# A folder, or a link to one, takes its name too: nothing goes inside.
mkdir "$dl/report.txt" "$work/elsewhere"
ln -s "$work/elsewhere" "$dl/linked.txt"
printf 'r' | deliver report.txt || fail "--deliver failed on a name a folder takes"
printf 'k' | deliver linked.txt || fail "--deliver failed on a name a link to a folder takes"
[[ $(<"$dl/report-1.txt") == r && $(<"$dl/linked-1.txt") == k ]] || fail "folder names: $(ls -A "$dl")"
[[ -z $(ls -A "$dl/report.txt") && -z $(ls -A "$work/elsewhere") ]] || fail "a file went inside a folder"
rm -rf "$dl/report.txt" "$dl/linked.txt" "$work/elsewhere"
# A file that cannot be saved fails and says so. Root writes through the
# read-only mode, so this part runs only as a user (CI's verify runs as root).
if ((EUID != 0)); then
  : >"$work/notes"
  chmod 0500 "$dl"
  if printf 'x' | deliver blocked.txt 2>/dev/null; then fail "--deliver succeeded into a read-only Downloads"; fi
  chmod 0700 "$dl"
  grep -qx 'Could not save blocked.txt | Taildrop will try again when the next file arrives' "$work/notes" ||
    fail "failure announcement: $(cat "$work/notes")"
fi
rm -rf "${dl:?}"/* "$dl"/.taildrop-* 2>/dev/null || true

# Send through the picker, to a machine by name.
export SUBCULT_FILE_CHOOSER=$work/chooser SUBCULT_TAILSCALE_HELPER=/usr/lib/subcult/tailscale-helper
: >"$work/notes"
"$root/bin/subcult-tailscale-send" kvant.tail1.ts.net || fail "send failed"
[[ $(cat "$work/pkexec-log") == "pkexec /usr/lib/subcult/tailscale-helper send 100.64.0.2 a file.pdf
pkexec /usr/lib/subcult/tailscale-helper send 100.64.0.2 b.txt" ]] || fail "pkexec calls: $(cat "$work/pkexec-log")"
[[ $(<"$work/sent") == AB ]] || fail "the files did not go as standard input: $(<"$work/sent")"
grep -qx -- '--title Send to kvant --multiple' "$work/chooser-log" || fail "picker title: $(cat "$work/chooser-log")"
grep -qx 'Sent to kvant | 2 files' "$work/notes" || fail "send announcement: $(cat "$work/notes")"

# An unknown machine: nothing sent, the picker not even opened.
rm -f "$work/pkexec-log" "$work/chooser-log"
if "$root/bin/subcult-tailscale-send" nowhere 2>/dev/null; then fail "an unknown machine succeeded"; fi
[[ ! -e $work/pkexec-log && ! -e $work/chooser-log ]] || fail "an unknown machine still went on"

# A closed picker sends nothing and is no error.
touch "$work/chooser-closed"
"$root/bin/subcult-tailscale-send" 100.64.0.2 || fail "a closed picker failed"
[[ ! -e $work/pkexec-log ]] || fail "a closed picker still sent"

# The panel's form: the address, and the name for the picker and the
# notification.
rm "$work/chooser-closed"
: >"$work/notes"
"$root/bin/subcult-tailscale-send" --name Phone 100.64.0.3 || fail "send --name failed"
grep -qx "pkexec /usr/lib/subcult/tailscale-helper send 100.64.0.3 b.txt" "$work/pkexec-log" ||
  fail "pkexec by address: $(cat "$work/pkexec-log")"
grep -qx -- '--title Send to Phone --multiple' "$work/chooser-log" || fail "picker title with --name: $(cat "$work/chooser-log")"
grep -qx 'Sent to Phone | 2 files' "$work/notes" || fail "send announcement with --name: $(cat "$work/notes")"
if "$root/bin/subcult-tailscale-send" --name 2>/dev/null; then fail "--name without a machine succeeded"; fi

# A file that is not there, and a failed transfer.
if "$root/bin/subcult-tailscale-send" 100.64.0.2 "$work/missing.txt" 2>/dev/null; then fail "a missing file succeeded"; fi
touch "$work/cp-fails"
if "$root/bin/subcult-tailscale-send" 100.64.0.2 "$work/b.txt" 2>/dev/null; then fail "a failed transfer succeeded"; fi
grep -qx 'Nothing sent to 100.64.0.2 | 100.64.0.2: no matching peer' "$work/notes" || fail "failure announcement: $(cat "$work/notes")"
echo "taildrop-test: ok"
