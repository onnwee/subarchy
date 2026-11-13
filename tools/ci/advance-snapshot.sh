#!/usr/bin/env bash
# Move the stable channel's Arch snapshot (default/pacman/snapshot, ADR 0026)
# forward to yesterday, but only after an ISO built on that day installs and
# passes every check of the VM install test.
#
# Runs on Kvant from the user timer in tools/ci/systemd/. Needs Docker with
# /dev/kvm and a `gh` login that may push branches and open pull requests on
# GitHub. On success it pushes a branch and opens a pull request, which merges
# itself once the required checks pass. On failure it opens an issue (or
# comments on the open one) with the end of the log, and stable stays where it
# is.
#
#   SUBARCHY_SNAPSHOT_WORK  working directory (default ~/.cache/subarchy-snapshot)
#   SUBARCHY_SNAPSHOT_DATE  try this day (YYYY/MM/DD) instead of yesterday
#   SUBARCHY_SNAPSHOT_DRY   1 to build and test without pushing or opening anything
set -euo pipefail

repo=subculture-collective/subarchy
work=${SUBARCHY_SNAPSHOT_WORK:-$HOME/.cache/subarchy-snapshot}
src=$work/repo
log=$work/last-run.log
mkdir -p "$work"
exec 9>"$work/lock"
flock -n 9 || { echo "advance-snapshot: another run holds $work/lock"; exit 0; }

if [[ -d $src/.git ]]; then
  git -C "$src" fetch -q --prune origin
else
  git clone -q "https://github.com/$repo.git" "$src"
fi
git -C "$src" checkout -q --detach origin/main

current=$(git -C "$src" show origin/main:default/pacman/snapshot)
candidate=${SUBARCHY_SNAPSHOT_DATE:-$(date -u -d yesterday +%Y/%m/%d)}
[[ $candidate =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || { echo "advance-snapshot: invalid date $candidate" >&2; exit 1; }
if [[ ! $candidate > $current ]]; then
  echo "advance-snapshot: stable is at $current; $candidate is not newer"
  exit 0
fi
if ! curl -sfI --max-time 30 -o /dev/null "https://archive.archlinux.org/repos/$candidate/core/os/x86_64/core.db"; then
  echo "advance-snapshot: the Arch Linux Archive has no $candidate yet"
  exit 0
fi

branch=chore/snapshot-${candidate//\//-}
if [[ ${SUBARCHY_SNAPSHOT_DRY:-0} != 1 ]] &&
  [[ -n $(gh pr list --repo "$repo" --head "$branch" --state all --json number --jq '.[].number') ]]; then
  echo "advance-snapshot: a pull request for $candidate already exists"
  exit 0
fi

avail=$(df -B1 --output=avail "$work" | tail -1)
((avail >= 60000000000)) || { echo "advance-snapshot: less than 60 GB free under $work" >&2; exit 1; }

git -C "$src" checkout -q -B "$branch" origin/main
echo "$candidate" >"$src/default/pacman/snapshot"
git -C "$src" -c user.name='SUBCULT Agent' -c user.email=info@subcult.tv -c commit.gpgsign=false \
  commit -q -m "chore(pacman): advance the stable snapshot to $candidate" \
  -m "An ISO built on the Arch Linux Archive's $candidate passed the VM install test (tools/ci/advance-snapshot.sh)." \
  default/pacman/snapshot

# The same container the KVM runner gives the iso workflow: privileged for
# mkarchiso's loop devices, KVM for the boot and install test, and capped
# inside the batch slice so it yields to interactive work.
name=subarchy-snapshot-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" --init --privileged --device /dev/kvm --cpus 4 --memory 8g \
  --cgroup-parent batch.slice --pull always archlinux:latest sleep infinity >/dev/null
docker cp "$src/." "$name:/src"

started=$(date -u +%FT%TZ)
status=0
docker exec "$name" bash -euo pipefail -c '
  pacman -Syu --noconfirm --needed git
  cd /src
  git config --global --add safe.directory /src
  tools/ci/build-iso.sh
  tools/ci/install-test.sh
' >"$log" 2>&1 || status=$?
echo "advance-snapshot: $candidate: build and install test exited $status (log $log)"

if [[ ${SUBARCHY_SNAPSHOT_DRY:-0} == 1 ]]; then
  exit "$status"
fi

if ((status == 0)); then
  checks=$(grep -cE '^install-test: ok ' "$log" || true)
  git -C "$src" push -q --force origin "$branch"
  gh pr create --repo "$repo" --head "$branch" --base main \
    --title "chore(pacman): advance the stable snapshot to $candidate" \
    --body "$(printf '%s\n' \
      "Moves the stable channel's Arch snapshot from \`$current\` to \`$candidate\` (ADR 0026)." \
      "" \
      "Before opening this, \`tools/ci/advance-snapshot.sh\` on Kvant built the ISO against that day of the Arch Linux Archive and ran the guided offline VM install test: $checks checks passed (run started $started)." \
      "" \
      "Opened by the weekly snapshot timer.")"
  exit 0
fi

title="Stable snapshot $candidate failed the install test"
body="$(printf '%s\n' \
  "\`tools/ci/advance-snapshot.sh\` tried to move the stable channel from \`$current\` to \`$candidate\`; the ISO build or VM install test failed (exit $status, run started $started). Stable stays at \`$current\`." \
  "" \
  "Last lines of the log (full log on Kvant: \`$log\`):" \
  "" \
  '```' \
  "$(tail -n 60 "$log")" \
  '```')"
existing=$(gh issue list --repo "$repo" --state open --search "\"Stable snapshot\" \"failed the install test\" in:title" \
  --json number --jq '.[0].number // empty')
if [[ -n $existing ]]; then
  gh issue comment "$existing" --repo "$repo" --body "$body" >/dev/null
else
  gh issue create --repo "$repo" --title "$title" --body "$body" >/dev/null
fi
exit "$status"
