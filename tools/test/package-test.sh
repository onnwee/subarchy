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
) || {
  # A failed test, panic, vet error or [setup failed] package is named far
  # above the log's end: show those lines first. When none matches, show
  # everything check() printed except passing packages.
  cause=$(grep -n -B2 -A25 -e '--- FAIL' -e '^panic:' -e '\[setup failed\]' -e '^# ' "$work/makepkg.log") ||
    cause=$(sed -n '/Starting check()/,$p' "$work/makepkg.log" | grep -Ev '^(ok|\?) ' | tail -80) || true
  head -120 <<<"$cause" >&2
  # A failure in build() never reaches check(); its cause is at the end.
  tail -30 "$work/makepkg.log" >&2
  fail "makepkg failed"
}

pkg=$(find "$work/out" -name 'subarchy-*.pkg.tar.zst' | head -1)
[[ -n $pkg ]] || fail "no package produced"

list=$(bsdtar -tf "$pkg")
for path in usr/bin/subcult usr/bin/sub usr/bin/tea usr/bin/subcult-docker-sudoless usr/lib/systemd/system/subcult-ufw-docker.service usr/bin/subcult-shell-set usr/share/subcult/default/shell/completions/_subcult usr/bin/subcult-app usr/bin/subcult-update usr/bin/subcult-hw usr/bin/subarchy-setup etc/os-release \
  usr/share/subcult/default/apps.toml usr/share/subcult/migrations/ usr/share/licenses/subarchy/LICENSE \
  usr/share/subcult/default/hypr/subcult.lua usr/share/subcult/default/hypr/user-hyprland.lua \
  usr/share/wayland-sessions/subarchy.desktop usr/lib/sddm/sddm.conf.d/subarchy.conf \
  usr/lib/sysctl.d/90-subarchy-hardening.conf usr/lib/systemd/resolved.conf.d/50-subarchy.conf \
  usr/lib/NetworkManager/conf.d/50-subarchy-dns.conf usr/lib/systemd/coredump.conf.d/50-subarchy.conf usr/lib/systemd/logind.conf.d/50-subarchy-power-key.conf \
  usr/lib/systemd/user/timers.target.wants/subcult-update-check.timer \
  usr/lib/udev/rules.d/90-subarchy-power.rules usr/bin/subcult-power-auto \
  usr/lib/udev/rules.d/70-subarchy-gpu.rules usr/share/uwsm/env-hyprland.d/50-subarchy-gpu \
  usr/bin/subcult-gpu-env usr/bin/subcult-gpu-run usr/bin/subcult-gpu-mode \
  usr/bin/subcult-secureboot-setup usr/bin/subcult-secureboot-status usr/bin/subcult-disk-tpm; do
  grep -qx "$path" <<<"$list" || fail "missing $path"
done

# Fingerprint unlock (#93) has its own PAM service; the password stack does
# not change and never names pam_fprintd.
for path in etc/pam.d/subcult-lock etc/pam.d/subcult-lock-fingerprint usr/share/subcult/lock/FingerprintModel.js usr/bin/subcult-setup-fingerprint; do
  grep -qx "$path" <<<"$list" || fail "missing $path"
done
bsdtar -xOf "$pkg" etc/pam.d/subcult-lock | grep -q pam_fprintd && fail "the lock's password stack runs pam_fprintd"
fpstack=$(bsdtar -xOf "$pkg" etc/pam.d/subcult-lock-fingerprint)
grep -Eq '^auth +requisite +pam_fprintd\.so$' <<<"$fpstack" || fail "the fingerprint stack does not require pam_fprintd"
# Only pam_fprintd can say yes; pam_faillock can only refuse (ADR 0063).
grep -E '^auth' <<<"$fpstack" | grep -Ev '^auth +(requisite|required) +pam_(fprintd|faillock)\.so( |$)' && fail "the fingerprint stack has another way in"
grep -Eq '^auth +requisite +pam_faillock\.so preauth nodelay$' <<<"$fpstack" || fail "the fingerprint stack ignores a faillock lockout"

# The lock ships videos, stills and the captures used to recolour them.
for name in beams decrypt matrix; do
  for ext in webm png; do
    path="usr/share/subcult/screensaver/$name.$ext"
    grep -qx "$path" <<<"$list" || fail "missing $path"
  done
  grep -qx "usr/share/subcult/screensaver/captures/$name.log.gz" <<<"$list" || fail "missing capture $name"
  bsdtar -xOf "$pkg" "usr/share/subcult/screensaver/$name.webm" >"$work/$name.webm"
  ffprobe -v error -show_entries stream=codec_name,width,height -of csv=p=0 "$work/$name.webm" | \
    grep -qx 'vp9,960,540' || fail "bad video $name"
done
for path in usr/bin/subcult-screensaver-render usr/share/subcult/screensaver/index.json \
  usr/lib/systemd/user/subcult-screensaver.service; do
  grep -qx "$path" <<<"$list" || fail "missing $path"
done

# Look layer (shell and look design): GTK, KDE, Chromium, kitty and Neovim defaults.
for path in usr/share/glib-2.0/schemas/90-subarchy.gschema.override etc/xdg/gtk-3.0/settings.ini \
  etc/xdg/gtk-4.0/settings.ini etc/xdg/kdeglobals usr/share/color-schemes/Pult.colors \
  etc/chromium/policies/managed/color.json \
  etc/xdg/kitty/kitty.conf etc/xdg/kitty/subcult-ink.conf \
  usr/share/nvim/site/colors/subcult-ink.lua usr/share/nvim/site/colors/subcult.lua \
  usr/share/nvim/site/plugin/subarchy-colors.lua; do
  mode=$(bsdtar -tvf "$pkg" "$path" 2>/dev/null | cut -c1-10) || true
  [[ $mode == -rw-r--r-- ]] || fail "missing $path or mode ${mode:-none}, want 0644"
done
# The GTK settings above name adw-gtk3-dark; without it GTK 3 falls back to
# light Adwaita, so the package must pull it in on upgrades too.
bsdtar -xOf "$pkg" .PKGINFO | grep -qx 'depend = adw-gtk-theme' || fail "does not depend on adw-gtk-theme"
for path in usr/share/icons/subcult-cursor/index.theme usr/share/icons/subcult-cursor/cursors/left_ptr \
  usr/share/icons/subcult-cursor/hyprcursors/default.hlc usr/share/icons/subcult-cursor/manifest.hl; do
  grep -qx "$path" <<<"$list" || fail "missing $path"
done
grep -qx usr/share/fontconfig/conf.avail/44-subarchy-roles.conf <<<"$list" || fail "missing font roles conf"
for path in usr/share/sddm/themes/subarchy/lockup-dark.png usr/share/subcult/lock/lockup-dark.png; do
  grep -qx "$path" <<<"$list" || fail "missing rendered lockup $path"
done
[[ $(bsdtar -tvf "$pkg" etc/fonts/conf.d/44-subarchy-roles.conf 2>/dev/null) == *"-> /usr/share/fontconfig/conf.avail/44-subarchy-roles.conf" ]] ||
  fail "font roles conf is not linked from /etc/fonts/conf.d"
# Files other Arch packages own must not be in this package (neovim owns
# /etc/xdg/nvim/sysinit.vim; default-cursors owns the default cursor theme).
for path in etc/xdg/nvim/sysinit.vim usr/share/icons/default/index.theme; do
  if grep -qx "$path" <<<"$list"; then fail "$path belongs to another Arch package"; fi
done
for path in usr/share/subcult/shell/shell.qml usr/share/subcult/shell/Bar.qml usr/share/subcult/shell/Commons/qmldir \
  usr/share/subcult/shell/widgets/index.json usr/lib/systemd/user/subcult-shell.service \
  usr/share/subcult/shell/widgets/ht3/Panel.qml usr/share/subcult/shell/services/Ht3.qml usr/bin/subcult-ht3 \
  usr/lib/systemd/user/graphical-session.target.wants/subcult-shell.service; do
  grep -qx "$path" <<<"$list" || fail "missing $path"
done
if grep -q '^usr/share/subcult/shell/.*tests/' <<<"$list"; then fail "shell tests are packaged"; fi
grep -qx "icon-theme='Papirus-Dark'" <(bsdtar -xOf "$pkg" usr/share/glib-2.0/schemas/90-subarchy.gschema.override) ||
  fail "GSettings override lacks Papirus-Dark"

if grep -qx etc/sudoers.d/50-subarchy-update <<<"$list"; then
  fail "the obsolete passwordless update grant is packaged"
fi

osr=$(bsdtar -xOf "$pkg" etc/os-release)
for want in 'NAME="Subarchy"' 'ID=subarchy' 'ID_LIKE=arch' 'VERSION_ID=0.0.0'; do
  grep -qx "$want" <<<"$osr" || fail "os-release lacks $want"
done

mkdir "$work/root"
bsdtar -xf "$pkg" -C "$work/root" usr
cmp "$work/root/usr/share/sddm/themes/subarchy/lockup-dark.png" \
  "$work/root/usr/share/subcult/lock/lockup-dark.png" || fail "greeter and lock artwork differ"
# The lockup's ink is centred, so it lines up with the caption and the clock.
read -r ink_left ink_width canvas < <(magick "$work/root/usr/share/subcult/lock/lockup-dark.png" -trim -format '%X %w %W\n' info:)
ink_right=$((canvas - ink_left - ink_width))
((${ink_left#+} - ink_right <= canvas / 50 && ink_right - ${ink_left#+} <= canvas / 50)) ||
  fail "lockup ink is off centre: ${ink_left#+} px left, $ink_right px right"
# The desktop's session units skip the greeter's sddm user, and none is a
# oneshot, which would hold back graphical-session.target and the bar.
for unit in "$work/root"/usr/lib/systemd/user/graphical-session.target.wants/*; do
  grep -qx 'ConditionUser=!@system' "$unit" || fail "$(basename "$unit") would start for the greeter's sddm user"
  if grep -qx 'Type=oneshot' "$unit"; then fail "$(basename "$unit") holds back graphical-session.target"; fi
done
# The timers every user gets skip sddm as well, and so do their services.
userunits=$work/root/usr/lib/systemd/user
for unit in "$userunits"/timers.target.wants/*.timer; do
  name=$(basename "$unit" .timer)
  for f in "$userunits/$name.timer" "$userunits/$name.service"; do
    grep -qx 'ConditionUser=!@system' "$f" || fail "$(basename "$f") would run for the greeter's sddm user"
  done
done
[[ -x $work/root/usr/lib/subcult/bluetooth-pair-agent ]] || fail "pairing helper is missing or not executable"
# Tailscale (ADR 0058) and lazydocker through polkit (ADR 0055).
for f in usr/lib/subcult/file-chooser usr/lib/subcult/lazydocker-root usr/lib/subcult/tailscale-helper \
  usr/lib/subcult/taildrop-receive usr/bin/subcult-tailscale-send usr/bin/subcult-docker-tui; do
  [[ -x $work/root/$f ]] || fail "$f is missing or not executable"
done
for f in usr/lib/systemd/system/subcult-taildrop@.service usr/share/applications/subcult-lazydocker.desktop; do
  [[ -e $work/root/$f ]] || fail "missing $f"
done
grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/lib/subcult/lazydocker-root</annotate>' \
  "$work/root/usr/share/polkit-1/actions/tv.subcult.docker.policy" || fail "the lazydocker polkit action does not name its program"
# The Tailscale panel's helper (ADR 0062): the action names it and lets the
# active session use it without a password; the receiver runs it as root.
ts_policy=$work/root/usr/share/polkit-1/actions/tv.subcult.tailscale.policy
grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/lib/subcult/tailscale-helper</annotate>' "$ts_policy" ||
  fail "the Tailscale polkit action does not name its helper"
{ grep -q '<allow_active>yes</allow_active>' "$ts_policy" && grep -q '<allow_any>auth_admin</allow_any>' "$ts_policy"; } ||
  fail "the Tailscale polkit action's defaults"
td_unit=$work/root/usr/lib/systemd/system/subcult-taildrop@.service
grep -qx 'ExecStart=/usr/lib/subcult/taildrop-receive %I' "$td_unit" || fail "subcult-taildrop@.service does not run the receiver"
# It starts whenever tailscaled does, and keeps only the rights to become the user.
grep -qx 'WantedBy=tailscaled.service' "$td_unit" || fail "subcult-taildrop@.service is not wanted by tailscaled"
grep -qx 'CapabilityBoundingSet=CAP_SETUID CAP_SETGID' "$td_unit" || fail "subcult-taildrop@.service keeps every capability"
# No user unit receives Taildrop files any more, and nothing grants
# tailscaled's operator role.
[[ ! -e $work/root/usr/lib/systemd/user/subcult-tailscale-receive.service ]] || fail "the old user receiver is packaged"
if grep -rlE -- '--operator(=|[[:space:]]|$)' "$work/root/usr/lib/subcult" "$work/root/usr/lib/systemd" "$work/root/usr/bin" \
  "$work/root/usr/share/subcult/migrations" 2>/dev/null; then
  fail "a packaged file sets tailscaled's operator"
fi
"$work/root/usr/bin/subcult" --version | grep -qx 'subcult 0.0.0' || fail "subcult --version"
"$work/root/usr/bin/subcult-app" validate "$work/root/usr/share/subcult/default/apps.toml" >/dev/null ||
  fail "shipped app catalogue does not validate"

"$root/tools/test/cursor-test.sh" "$work/root/usr/bin/subcult-cursor" || fail "cursor test"

# Neovim: the subcult scheme (ADR 0045) when the user picked no scheme, the user's scheme otherwise.
if command -v nvim >/dev/null; then
  nv="$work/nvim"
  mkdir -p "$nv/cfg/nvim" "$nv/home"
  scheme() {
    HOME=$nv/home XDG_CONFIG_HOME=$nv/cfg XDG_CONFIG_DIRS=$nv/none XDG_DATA_HOME=$nv/home/data \
      XDG_STATE_HOME=$nv/home/state XDG_DATA_DIRS="$work/root/usr/share:/usr/share" \
      nvim --headless +'lua io.write(vim.g.colors_name or "none")' +qa 2>/dev/null
  }
  [[ $(scheme) == subcult ]] || fail "Neovim does not default to subcult"
  echo 'vim.cmd.colorscheme("habamax")' >"$nv/cfg/nvim/init.lua"
  [[ $(scheme) == habamax ]] || fail "Neovim overrides the user's colour scheme"
fi

echo "package-test: ok ($(basename "$pkg"), $(wc -l <<<"$list") entries)"
