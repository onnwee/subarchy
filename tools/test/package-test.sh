#!/usr/bin/env bash
# Builds the subarchy package with makepkg into a temporary directory and
# checks its contents. Needs an Arch system with makepkg; run as a normal user.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
cleanup() { rm -r -- "$work"; }
trap cleanup EXIT

fail() { echo "package-test: $*" >&2; exit 1; }

# Skip makedepends checks when Go comes from mise rather than pacman.
nodeps=()
pacman -T go >/dev/null 2>&1 || nodeps=(--nodeps)

(
  cd "$root/packaging/subarchy"
  BUILDDIR="$work/build" PKGDEST="$work/out" SRCDEST="$work/src" \
    makepkg --force --cleanbuild --noconfirm "${nodeps[@]}" >"$work/makepkg.log" 2>&1
) || { tail -30 "$work/makepkg.log" >&2; fail "makepkg failed"; }

pkg=$(find "$work/out" -name 'subarchy-*.pkg.tar.zst' | head -1)
[[ -n $pkg ]] || fail "no package produced"

list=$(bsdtar -tf "$pkg")
for path in usr/bin/subcult usr/bin/sub usr/bin/subcult-app usr/bin/subcult-update usr/bin/subcult-hw usr/bin/subarchy-setup etc/os-release \
  usr/share/subcult/default/apps.toml usr/share/subcult/migrations/ usr/share/licenses/subarchy/LICENSE \
  usr/share/subcult/default/hypr/subcult.lua usr/share/subcult/default/hypr/user-hyprland.lua \
  usr/share/wayland-sessions/subarchy.desktop usr/lib/sddm/sddm.conf.d/subarchy.conf \
  usr/lib/sysctl.d/90-subarchy-hardening.conf usr/lib/systemd/resolved.conf.d/50-subarchy.conf \
  usr/lib/NetworkManager/conf.d/50-subarchy-dns.conf usr/lib/systemd/coredump.conf.d/50-subarchy.conf \
  etc/sudoers.d/50-subarchy-update usr/lib/systemd/user/timers.target.wants/subcult-update-check.timer \
  usr/lib/udev/rules.d/90-subarchy-power.rules usr/bin/subcult-power-auto \
  usr/lib/udev/rules.d/70-subarchy-gpu.rules usr/share/uwsm/env-hyprland.d/50-subarchy-gpu \
  usr/bin/subcult-gpu-env usr/bin/subcult-gpu-run usr/bin/subcult-gpu-mode \
  usr/bin/subcult-secureboot-setup usr/bin/subcult-secureboot-status usr/bin/subcult-disk-tpm; do
  grep -qx "$path" <<<"$list" || fail "missing $path"
done

# Look layer (shell and look design): GTK, kitty and Neovim defaults.
for path in usr/share/glib-2.0/schemas/90-subarchy.gschema.override etc/xdg/gtk-3.0/settings.ini \
  etc/xdg/gtk-4.0/settings.ini etc/xdg/kitty/kitty.conf etc/xdg/kitty/subcult-ink.conf \
  usr/share/nvim/site/colors/subcult-ink.lua etc/xdg/nvim/sysinit.vim; do
  mode=$(bsdtar -tvf "$pkg" "$path" 2>/dev/null | cut -c1-10) || true
  [[ $mode == -rw-r--r-- ]] || fail "missing $path or mode ${mode:-none}, want 0644"
done
for path in usr/share/icons/subcult-cursor/index.theme usr/share/icons/subcult-cursor/cursors/left_ptr \
  usr/share/icons/subcult-cursor/hyprcursors/default.hlc usr/share/icons/subcult-cursor/manifest.hl; do
  grep -qx "$path" <<<"$list" || fail "missing $path"
done
grep -qx "icon-theme='Papirus-Dark'" <(bsdtar -xOf "$pkg" usr/share/glib-2.0/schemas/90-subarchy.gschema.override) ||
  fail "GSettings override lacks Papirus-Dark"

perm=$(bsdtar -tvf "$pkg" etc/sudoers.d/50-subarchy-update | cut -c1-10)
[[ $perm == -r--r----- ]] || fail "sudoers drop-in mode $perm, want 0440"

osr=$(bsdtar -xOf "$pkg" etc/os-release)
for want in 'NAME="Subarchy"' 'ID=subarchy' 'ID_LIKE=arch' 'VERSION_ID=0.0.0'; do
  grep -qx "$want" <<<"$osr" || fail "os-release lacks $want"
done

mkdir "$work/root"
bsdtar -xf "$pkg" -C "$work/root" usr
"$work/root/usr/bin/subcult" --version | grep -qx 'subcult 0.0.0' || fail "subcult --version"
"$work/root/usr/bin/subcult-app" validate "$work/root/usr/share/subcult/default/apps.toml" >/dev/null ||
  fail "shipped app catalogue does not validate"

"$root/tools/test/cursor-test.sh" "$work/root/usr/bin/subcult-cursor" || fail "cursor test"

echo "package-test: ok ($(basename "$pkg"), $(wc -l <<<"$list") entries)"
