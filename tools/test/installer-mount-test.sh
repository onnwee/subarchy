#!/usr/bin/env bash
# Root-only regression for arch-chroot's private /run bind retaining the
# install mount in live-service namespaces. Uses only a private tmpfs tree.
set -euo pipefail

((EUID == 0)) || { echo "installer-mount-test: run as root" >&2; exit 2; }
if [[ ${SUBARCHY_MOUNT_TEST_NS:-} != 1 ]]; then
  exec unshare --mount --propagation private env SUBARCHY_MOUNT_TEST_NS=1 bash "$0"
fi

work=$(mktemp -d /run/subarchy-mount-test.XXXXXX)
observer=""
cleanup() {
  if [[ -n $observer ]]; then
    kill "$observer" 2>/dev/null || true
    wait "$observer" 2>/dev/null || true
  fi
  umount -R "$work" 2>/dev/null || true
  rmdir "$work"
}
trap cleanup EXIT
mount -t tmpfs -o size=4M tmpfs "$work"
mount --make-shared "$work"
mkdir "$work/target" "$work/run"
mkdir "$work/run/credentials"
# shellcheck disable=SC2016 # Expanded by the observer shell.
unshare --mount --propagation slave sh -c 'echo ready > "$1/ready"; exec sleep 120' sh "$work" &
observer=$!
for ((i=0; i<50; i++)); do
  [[ -e $work/ready ]] && break
  sleep 0.1
done
[[ -e $work/ready ]]

# Reproduce the old install: the bind becomes private in this namespace,
# leaving a copy in the slave namespace when our tree is unmounted.
mount -t tmpfs tmpfs "$work/target"
mkdir "$work/target/run"
mount --bind --make-private "$work/run" "$work/target/run"
# A service credential mount appears after arch-chroot made its bind private.
# It reaches the observer's bind, leaving a child mount unknown to us.
mount -t tmpfs tmpfs "$work/run/credentials"
umount -R "$work/target"
nsenter -t "$observer" -m -- mountpoint -q "$work/target"
echo "installer-mount-test: reproduced leaked mount without isolation"
nsenter -t "$observer" -m -- umount -R "$work/target"
umount "$work/run/credentials"

# The install's new outer private namespace prevents propagation to the
# observer, including arch-chroot's later private bind.
# shellcheck disable=SC2016 # Expanded by the isolated shell.
unshare --mount --propagation private sh -eu -c '
  mount -t tmpfs tmpfs "$1/target"
  mkdir "$1/target/run"
  mount --bind --make-private "$1/run" "$1/target/run"
  umount -R "$1/target"
' sh "$work"
if nsenter -t "$observer" -m -- mountpoint -q "$work/target"; then
  echo "installer-mount-test: FAIL: isolated mount leaked" >&2
  exit 1
fi
echo "installer-mount-test: PASS: private namespace leaves no retained mount"
