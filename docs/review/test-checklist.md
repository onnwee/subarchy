---
title: "Hardware test checklist"
type: review
status: draft
review: pending
created: 2026-11-13
updated: 2026-11-13
tags: [review, testing, hardware]
aliases: [Test checklist, Owner test checklist]
---

# Hardware test checklist

What the owner tests by hand on sputnik before the first release. CI and the
VM install test already cover what a VM can show; everything here needs the
real laptop, its dock and peripherals, an account, or an owner decision.
Results feed [GitHub #51](https://github.com/subculture-collective/subarchy/issues/51)
and the acceptance table in [[first-install]].

**What to test.** Main as of 2026-11-13 (`6b4c2fb` or later). Use either the
ISO from Gitea's `iso` workflow (artifact `subarchy-iso`, kept for 2 days) or
the stick the lead writes on Soyuz. Update the installed system with
`subcult update` before the desktop sections. F7, D20 and C2 expect
#183, #184 and #185 to have merged.

**How to report a failure.** Note the item ID (for example I9), what you did,
what happened instead, and a photo of the screen or the output of the command
the item names. Put it on #51, or on the issue the item names.

**Markers.**

- **(retest)**: this failed before and a fix has merged since.
- **(new)**: merged, but never run on real hardware.
- **(diagnostic)**: collects output for an open problem; it passes once the
  output is attached to the issue it names.
- **(decision)**: needs an answer, not a test. These are collected in
  [[#13 Decisions for the owner]].

**Two sittings.** Section 0 runs on the current install, including C3 and C4,
which need a system installed before 2026-11-13. Sections 1–3 cover the
stick, the installer and first boot, and end with a fresh install; F15 brings
back your home, Bluetooth pairings and tailnet sign-in. Sections 4–12 run on
that install. Items that need hardware other than sputnik are in
[[#14 Other hardware (optional)]].

## 0 Before you start

- [ ] **B1** Get the ISO: download `subarchy-iso` from a Gitea `iso` run on main, run `make iso`, or take the lead's stick. Run `sha256sum` on the file. *Expect:* one `subarchy-YYYY.MM.DD-x86_64.iso` of about 7 GB (6.95 GB on 2026-11-14, with the full app list in its offline repository); write its hash down. (iso/README.md)
- [ ] **B2** Write it to the stick by `/dev/disk/by-id/...` with `dd bs=4M oflag=direct conv=fsync`, then read back exactly the ISO's size and hash it. *Expect:* the hashes match; `blkid` shows the label `SUBARCHY_YYYYMM`.
- [ ] **B3** Back up your home on the current Subarchy install. A guided install erases the disk you choose. Install only onto the SPCC disk (serial `AA231221NV01KG05237`), never the Crucial CT1000P5 disk (Omarchy).
- [ ] **B4** On the current install, before reinstalling, run **C3** and **C4**. Both need a system installed before 2026-11-13.
- [ ] **B5** Run `subcult hw info`, `subcult hw fingerprint; echo $?` and `lsusb`. *Expect:* `subcult hw fingerprint` exits 0 when it finds a fingerprint reader and 1 when it does not (the probe K10 uses); `lsusb` shows whether the dock is a DisplayLink device. Note both.

What to have at hand, and what to skip without it:

| Missing | Skip |
|---|---|
| Dock with the two ONN panels | M2–M5, P10 |
| Wired headphones | the jack part of A1 |
| TOZO HT3 headphones | A4, A5 |
| Another Bluetooth device | A2, A3 |
| Fingerprint reader | K10–K12 |
| Spare USB drive or disk of 20 GiB or more that you can erase (smaller disks are hidden) | I7's USB part, I16's Stay part, I18–I21 |
| Webcam (built in or USB) | the camera part of D11 |
| Second machine on the LAN | the port probe in T6 |
| Phone with LocalSend (and the TOZO app) | N6, the phone part of A4 |
| Second tailnet machine, Tailscale account | N3, N4 |
| Proton, Discord, Anthropic or OpenAI account | the matching parts of T2, N5, D29 |
| CalDAV account or iCal URL | D18 |
| n8n server and API key | D26 |
| Google account | nothing yet: Google calendar (#89) is not built |

## 1 Live boot

- [ ] **L1** (retest) Boot the stick with F12 and time the gap from the boot menu to the installer. *Expect:* the menu shows "Subarchy install medium (x86_64, UEFI)", "… with speech" and Memtest86+ for 2 s with a beep. Boot text appears within a few seconds, with no 30 s black screen. No root autologin banner or motd flashes, and no `[ OK ]` lines print over the installer. The installer starts on tty1 in a large Terminus font. (#144, #125)
- [ ] **L2** Reboot and pick "… with speech". *Expect:* the sound check plays, espeakup reads the console aloud, and the installer still starts.
- [ ] **L3** Pick Memtest86+, then exit it. *Expect:* it runs, and exiting returns to the firmware.
- [ ] **L4** Press Alt+F2; on tty1, leave the installer with Esc. *Expect:* tty2 is a root shell; tty1 drops to a shell that prints the motd help.
- [ ] **L5** From tty2 (or SSH from another machine) run `subarchy-setup --plain`, then quit it. *Expect:* plain line prompts: keyboard first, a numbered Wi-Fi list, then disks of 20 GiB or more without the install medium, with `look N` to browse.
- [ ] **L6** Run `uname -r` and write it down for F5.

## 2 Installer

Run the installer on tty1 with the dock unplugged, so Ethernet is off.

- [ ] **I1** On Language, pick a non-English language. *Expect:* the installer stays in English, the next page preselects that language's keyboard, and Escape on any screen goes back one step.
- [ ] **I2** Choose a keyboard layout. *Expect:* the console switches layout at once, so later passwords use it.
- [ ] **I3** (retest) On the Wi-Fi page, choose "Look for networks again", enter a wrong passphrase once, then the right one. Try a 64-character hex key. *Expect:* networks are listed strongest first, with control-character names hidden. The wrong passphrase gives an error and you stay on the page. The hex key is refused. The right passphrase gets an address within 20 s. 802.1X and WEP networks are listed but cannot be joined. Optional: repeat on a WPA3-only network. (#149)
- [ ] **I4** (new) Reach the time zone page while online, then type `chi` in its search. *Expect:* "Looking up the time zone..." appears, then the list opens on America/Chicago with a note saying the guess came from the network. In CI the lookup only ever answered "none", so it has never been seen working. `chi` lists America/Chicago first, with no `US/*` or `Canada/*` aliases. Time zone and computer name sit under "Let's set up your machine.", and the confirm prompt lines up with the heading. (#155, #142)
- [ ] **I5** Enter an uppercase user name, a password under 8 characters and a bad computer name, then valid ones. *Expect:* each answer is checked as you type it, with a notice.
- [ ] **I6** At "The disk is always encrypted.", answer "No, a separate passphrase" and set one. *Expect:* it asks for the disk passphrase separately.
- [ ] **I7** Open the disk list with a second USB disk plugged in. *Expect:* internal NVMe disks first and USB disks after; the live stick is not listed; SPCC and Crucial are told apart by model and serial; partitions show as `vfat "EFI"` and `encrypted (LUKS) "subarchy-luks"`, the same as on the "On /dev/... now:" screen. (#155)
- [ ] **I8** (retest) Pick the SPCC disk, choose "Browse it read-only first" and read the page. Press Escape once to check it goes back, then return and press Return. *Expect:* the page lists the partitions opened read-only and names each skipped one with its reason, for example `encrypted (LUKS) "subarchy-luks", left locked`. It ends with "To come back here, press q, or Esc and then 0, / or F10 (Fn+F10 on many laptops)." Escape goes back without opening mc. In mc, both panels (Tab switches) are on `/run/subarchy-look`, never the live `/root`. (#143)
- [ ] **I9** (retest) In that mc, type `touch /tmp/PWNED` and Return, `10` and Return, `:10` and Return; press Ctrl-O, then F2; press Return on an `.efi` or `.conf` file on the EFI partition. Quit, choose "Open a shell" and run `ls /tmp/PWNED`. *Expect:* no command line and no hint bar; typing only starts the panel's quick search; Ctrl-O and F2 do nothing; Return on a file runs nothing; `/tmp/PWNED` does not exist. (#143)
- [ ] **I10** (retest) In mc, open the F9 menu bar and a pull-down. *Expect:* pale text on ink, yellow hotkeys, and a readable selected row (paper on violet), judged by eye on the panel. (#143)
- [ ] **I11** (retest) Leave mc three times, once each with q, with Esc then 0, and with Fn+F10. *Expect:* each one returns to the "On /dev/nvme… now:" options; the laptop never has to be powered off. Optional: browse a disk that holds only LUKS or swap. *Expect:* "Nothing on /dev/X can be opened read-only.", and Return goes back. (#143)
- [ ] **I12** (retest) Choose "Choose a different disk", then pick SPCC again. Go on to the summary, answer "No, change it", then come back. *Expect:* the disk list reopens with the cursor on the disk you looked at last. The summary lists every answer, with the disk "(erased)", Wi-Fi "(joined at first boot)", and both password rows "set (hidden)" with no length. "No" goes back. (#142)
- [ ] **I13** On "Does this look right?" and "Yes, erase and install", move focus between the buttons. *Expect:* the erase question comes last and defaults to no. Judge by eye, not through a camera, whether the focused label (ink on acid green) is easy to read; if it is not, answer Q5. Nothing has changed here since the last run: the earlier verifier blamed the camera.
- [ ] **I14** (retest) Install onto SPCC and watch the bar until "finishing". Write down how long the DKMS stage takes. *Expect:* before the first package unpacks, the label names pacman's step ("Getting the packages ready", "Downloading packages", "Checking the package keys"…), and "Installing packages (0 of N)" never shows. Later it reads "Setting up packages (n of m)" and keeps moving through the DKMS and boot-image builds, with no 3-minute freeze at 70% and no long hold at 97%. At 0–5% the empty track (░) looks clearly lighter than the filled part. The rotating tips fit inside the logo width, are centred and show no backticks; the font is a comfortable size on the 4K panel. (#142, #144, #126, #128, #131)
- [ ] **I15** (retest) During the install, press L, watch through pacman's coloured output, and press L again. *Expect:* the log tail shows and hides, with no raw escape text such as `[0m`, and long lines end in "…". The full log is `/var/log/subarchy-install.log`. (#142)
- [ ] **I16** (retest) Let it finish and choose "Reboot now". *Expect:* the installer exits cleanly, with the final LUKS close succeeding, and says how long it took. The console palette resets and the screen clears, with no "Failed to reset /dev/console", watchdog or `[ OK ]` lines over the background. The finish screen offers only "Reboot now" and "Stay in the live system"; check Stay on the spare-disk install in I20, where it should leave a live shell in the console's normal colours. (#99, #142)
- [ ] **I16a** If the laptop starts Omarchy or the firmware's fallback instead of the new install, that is expected (see I17): press F12, pick the new Limine entry for the SPCC disk (tell the two Limine entries apart by the partition GUID `efibootmgr -v` prints; the SPCC ESP's GUID is in `lsblk -o NAME,PARTUUID` on the installed system), then make it the default in the firmware setup or with `sudo efibootmgr -o` after reading the entry numbers again.
- [ ] **I17** (new) After the reboot, open the F12 menu, and later run `efibootmgr -v` on the installed system. *Expect:* the earlier Subarchy entry `0005` "Subarchy (SPCC)" is gone, since its partition no longer exists, and a new entry labelled "Limine" points at the new SPCC ESP. Omarchy's `0002` and its Crucial ESP are untouched. Note where the new entry sits in BootOrder; it is likely not first, so the firmware starts Omarchy until you change the order as in I16a. Both Limine entries still read "Limine" (known; see Q2). (#140)
- [ ] **I18** On a spare disk or USB drive only, never SPCC or Crucial: go through the installer up to "Yes, erase and install", then switch to tty2 and mount one partition of that disk (`mkdir /tmp/m && mount /dev/sdX1 /tmp/m`; a USB drive with a FAT partition works). Back on tty1, confirm the install. On the failure screen, open View the full log and leave it, then choose Open a shell. *Expect:* the failure screen gives subarchy-install's own reason ("DISK /dev/sdX has mounted partitions"), not "exit status 1" or a pult warning. It shows only this run's log lines and offers View the full log, Open a shell, Reboot and Power off. Open a shell leaves a shell in the console's normal colours. Optionally repeat and choose Power off: the machine powers off. Unmount with `umount /tmp/m` afterwards. (#124, #155)
- [ ] **I19** In the live system, first run `findmnt /run/archiso/bootmnt`. If it prints nothing, the image was copied to RAM and the stick may not be protected: skip the stick run below and report it on #51. Otherwise write `/tmp/t.conf` with `DISK=/dev/disk/by-id/<the spare disk>`, `HOSTNAME=test`, `USERNAME=tester`, `USER_PASSWORD_FILE=/tmp/pw`, `LUKS_PASSPHRASE_FILE=/tmp/pw` and `SUBARCHY_REPO=file:///opt/subarchy/repo`, and run `echo testtest >/tmp/pw`. Find the by-id names with `ls -l /dev/disk/by-id/`. Then run `subarchy-install --config /tmp/t.conf` (no `--yes`); set `DISK` to the live stick's by-id path and run it with `--yes`; set `DISK` back to the spare disk and `USERNAME=docker`, and run it again without `--yes`. *Expect:* each run stops before wiping anything, with in turn "this wipes …; pass --yes to continue", a refusal naming the stick ("has mounted partitions" or "is the install medium"), and "USERNAME: docker is a system account or group". Point `DISK` only at the stick or the spare disk.
- [ ] **I20** (new) On the spare disk or USB drive only, install twice. First with the dock's Ethernet plugged in: the Wi-Fi page should not appear. Then with Ethernet unplugged and the language left on English (US): on the Wi-Fi page choose "Skip, install offline", and at the end choose "Stay in the live system". *Expect:* the wired run skips straight past Wi-Fi and installs. The offline run asks no network lookup on the time zone page and opens it on UTC with no note (a language such as German opens on its country's zone, Europe/Berlin, with "Guessed from the language you chose."). Pressing L during package install shows "no mirror reachable: installing from the image's repository alone", and the install finishes from `/opt/subarchy/repo`. Stay leaves a live shell in normal colours.
- [ ] **I21** (new) On the spare disk or USB drive only: start an online install (Wi-Fi or Ethernet), press L, and as soon as the log shows pacman synchronizing its databases or downloading packages, pull the network. If pacman downloads nothing because the image already holds every package, this cannot trigger the retry; note that and skip the item. *Expect:* the log shows "installing from the mirrors failed; trying again from the image's repository alone", the second package install runs from the image, and the install finishes. That retry has never run outside tests. If it fails instead, the failure screen should name the step and give subarchy-install's reason. (#118)

## 3 First boot and unlock

- [ ] **F1** Watch the Limine menu. *Expect:* themed, with entries in the order linux-zen, linux-lts, fallbacks, Snapshots.
- [ ] **F2** (diagnostic) Time the gap from Limine's "Booting automatically" to the Plymouth prompt (about 11 s of black today). Afterwards, run `systemd-analyze`, `journalctl -b -o short-monotonic | grep -Ei 'plymouth|i915|nvidia|simpledrm|drm|cryptsetup|modules-load'` and `ls -lh /boot/EFI/Linux/` and attach the output. Optional: boot once with `plymouth.use-simpledrm` added at the Limine menu (press e). *Expect:* no fix has merged, so the gap is still there. The item passes once the gap's length and the output are on #51; they show whether the NVIDIA modules in the initrd cause it, which Q22 needs. (internal/hw/fixes.go)
- [ ] **F3** (retest) At the Plymouth prompt, undocked and again docked: read it, type a passphrase longer than 16 characters, enter a wrong passphrase four or five times, then the right one. *Expect:* the graphical SUBCULT splash, not text mode, with a "Disk passphrase" label above the field. The bullets stay inside the field. Each wrong try shows "That passphrase didn't work. Try again." under the field and returns to the same prompt. No emergency mode, no "root account is locked" and no plain-console prompt. The right passphrase boots. (#144, #123)
- [ ] **F4** Boot the linux-lts entry once and run `dkms status`. *Expect:* it reaches the greeter, and the NVIDIA and evdi modules are built for both kernels.
- [ ] **F5** Compare `uname -r` with L6. *Expect:* the installed linux-zen is the same as the live one or newer. If it is older, that is the known live-root mismatch (Q3).
- [ ] **F6** (retest) Without touching the network, check it on first boot. *Expect:* the Wi-Fi joined in the installer connects by itself (the filmed install came up offline); dock Ethernet gets DHCP. (#149)
- [ ] **F7** (retest) At the greeter, check the User field, the focus, and whether the bar shows. Press Super+1, Super+Space and Super+Return. *Expect:* the User field holds the account the installer made and the focus is on Password. No bar or desktop panels, the keys do nothing, and the form never disappears. From a TTY, `ps -u sddm -o comm` shows no quickshell. (new) `systemctl --user -M sddm@ list-timers` lists none of the `subcult-*` timers (#183). (#145, #164)
- [ ] **F8** Sign in with the right password at the first try and time it. *Expect:* the bar appears within a few seconds, not after 14.5 s of empty blue. No "Hyprland updated to …" window or donation popup on this start or the next one. (#145)
- [ ] **F9** (retest) Sign out. At the greeter, turn Caps Lock on and type a letter, then enter a wrong password 10 times. Wait 2 minutes and sign in. *Expect:* the Caps Lock tag appears; a wrong password shows "Checking…" then an error. After 10 failures it shows PAM's text, for example "The account is locked due to 10 failed logins. (2 minutes left to unlock)". After 2 minutes the right password works without a reboot. (#145, #147)
- [ ] **F10** Look at the greeter beside the lock screen and the Plymouth prompt, at scale 1.6 and 2, and on a dock panel. Tab and Shift+Tab through the fields and press Escape in each. Repeat after `subcult theme apply-system` (T9). *Expect:* the SC mark is not doubled or offset; the "Subarchy" caption is centred; fields are labelled with visible focus; the layout matches the lock screen. Known gap: before apply-system the field border is violet #8B5CF6. Accept the look or list changes on #104. (#104, #148, #130)
- [ ] **F11** Run `systemctl --failed`, `systemctl --user --failed`, `sudo ufw status`, `sudo aa-status`, `resolvectl status`, `hyprctl configerrors` and `systemctl --user status subcult-shell subcult-idle subcult-clipboard subcult-display`. *Expect:* no failed units. ufw denies incoming except 53317 tcp/udp. AppArmor is on. DNS is Quad9 over strict DNS-over-TLS. No config errors. The four units are active.
- [ ] **F11a** With Secure Boot still off, run `sudo subcult disk tpm enable`, then `sudo subcult disk tpm status`. *Expect:* it refuses with "turn Secure Boot on first (sudo subcult secureboot setup)", and status still says "TPM unlock: off". (ADR 0010)
- [ ] **F12** After Q1: run `subcult secureboot status`, put the firmware in setup mode, run `sudo subcult secureboot setup`, and reboot with Secure Boot enforced. Take a snapshot and boot again. *Expect:* `sbctl verify` is clean. The enforced boot reaches the LUKS prompt, also after the snapshot rewrites `limine.conf`. NVIDIA DKMS still loads. Omarchy still boots from F12. (ADR 0012, ADR 0063)
- [ ] **F13** With Secure Boot on, run `sudo subcult disk tpm enable`, reboot, then `sudo subcult disk tpm status`. *Expect:* root unlocks with no prompt (PCR 7) and status says "TPM unlock: on". (ADR 0010)
- [ ] **F14** Turn Secure Boot off once, or run `sudo subcult disk tpm disable`. *Expect:* the boot asks for the passphrase and it unlocks; `disable` removes the tpm2-device option and the slot.
- [ ] **F15** Before section 4, restore what the reinstall dropped: copy back the files you need from the B3 backup, pair your Bluetooth devices again (A2 does this through the panel), and sign in to Tailscale again (N3 does this through the panel). *Expect:* the restored files open; A3, A4, N4 and N5 then have their devices and tailnet.

## 4 Desktop and bar

### Keys and windows

- [ ] **D1** Press Super+Return, Super+Shift+F and Super+Shift+B. *Expect:* kitty, Dolphin, and Chromium. Super+Shift+B runs `xdg-open https://`, and Chromium is the only browser installed; Zen is the catalogue default but is not installed (Q10). Any other browser is a failure.
- [ ] **D2** Try Super+W and Super+Q (close), Super+J (split), Super+T (float), Super+F (full screen), Super+Alt+F (full width) and Super+arrows. Then Super+1…0, Super+Shift+number and Super+S, and drag with Super+left and Super+right mouse. *Expect:* each works; workspace switches show the name in the OSD; Super+S toggles the scratchpad.
- [ ] **D3** Press Super+Shift+Escape. *Expect:* the session ends cleanly and SDDM returns.
- [ ] **D4** Add `sub.bind("SUPER + ALT + U", "Update", sub.alias("up"))` to `~/.config/hypr/hyprland.lua` with a launcher alias `up`, and run `hyprctl reload`. Then toggle motion off and on in settings and unplug AC. *Expect:* the bind works on top of the defaults, and your own look-and-feel settings survive the reloads. (#115)
- [ ] **D5** Press the volume, mute, mic-mute and brightness keys, also at the lock screen; press Caps Lock both ways. *Expect:* 5% volume steps and brightness steps with the OSD; the OSD shows "Caps Lock on" / "off" and the key still toggles. (#117)
- [ ] **D6** Look for a screenshot key, then run `grim -g "$(slurp)" - | satty -f -`. *Expect:* no key is bound (Q9); the command captures a region into satty.

### Bar

- [ ] **D7** Undocked, look at the bar. *Expect:* left: menu, workspaces, active window; centre: indicators to weather; right: keyboard to battery.

### Menu and settings

- [ ] **D8** Click the menu widget, change the Cursor, Idle, Motion and Bar layout groups, press Apply, then Undo last. *Expect:* the panel previews the changes, writes only under `~/.config/subcult`, and Undo restores the old values.

### Workspaces and active window

- [ ] **D9** Open windows on several workspaces, click slots, and change focus. *Expect:* occupied and active slots are marked, a click switches, and the active-window title follows each focus change.

### Indicators and microphone

- [ ] **D10** Click the keep-awake indicator, leave the machine idle past 15 minutes, then restart the shell. *Expect:* `systemd-inhibit --list` shows SUBCULT; nothing locks or suspends; the state survives the restart.
- [ ] **D11** Record with `pw-record /tmp/a.wav`, share the screen from a browser or OBS, and use the webcam. *Expect:* the microphone, screen and camera marks light while each is in use and clear afterwards. (#177)
- [ ] **D12** Click the microphone widget. *Expect:* the default source mutes and unmutes, like the mic-mute key.

### Audio

- [ ] **D13** Scroll on the audio widget with the mouse and the touchpad, middle-click it, and switch output and input in its panel. *Expect:* 5% steps with the OSD; middle-click mutes; a switch does not flash the OSD, and the first volume change after it shows the new output's volume. (#169, #171)

### Media and SomaFM

- [ ] **D14** Play something in mpv or the browser; click, middle-click and scroll the media widget. *Expect:* click plays or pauses; middle-click opens the panel with previous and next.
- [ ] **D15** In the SomaFM panel, filter and play a channel, then stop it. *Expect:* now-playing updates on song change; stopping leaves no mpv running.

### Clock and calendar

- [ ] **D16** Watch the clock across a minute, then open the calendar panel and change months. *Expect:* it ticks on the minute; days with events are marked and a click lists them.
- [ ] **D17** Set `widgets."subcult.world-clock".zones` to `["Europe/Berlin","Asia/Tokyo"]` in `~/.config/subcult/shell/bar.json`. *Expect:* the widget shows both times.
- [ ] **D18** Write `~/.config/subcult/calendar.toml` with an iCal feed and a CalDAV source (password via `secret-tool store service subcult-calendar source <name>`). Run `subcult calendar sync`, `status` and `list`. *Expect:* events show in the bar and panel; status shows each source. (ADR 0061)

### Updates

- [ ] **D19** (retest) With updates pending, click the update count. *Expect:* a terminal runs `subcult update`; afterwards the count drops to the true remainder and hides at 0.

### Weather

- [ ] **D20** (new) Run `pacman -Q linecast`, then open the weather panel and search for a location. *Expect:* linecast is installed; current conditions and the forecast show, and search finds the place. (#184)

### Keyboard layout, tray, display

- [ ] **D21** Add a second XKB layout in `hyprland.lua` and switch. *Expect:* the widget shows the active code (US, DE).
- [ ] **D22** Run Proton VPN, Signal and qBittorrent, then left-, right- and middle-click their tray icons. *Expect:* menus open and the secondary action runs; a Passive tray item stays hidden. (#170)
- [ ] **D23** Hover the display widget on each output. *Expect:* the tooltip names that output's connector.

### Notifications

- [ ] **D24** Run `notify-send hi` and `notify-send -u critical x`, open the panel, then right-click the bell. *Expect:* popups appear top right; hovering pauses the timeout; the critical one stays; the panel has Remove and Clear all; right-click toggles Do not disturb.

### Optional widgets

- [ ] **D25** Add `subcult.agents`, `subcult.downloads` and `subcult.auto-wallpaper` to the layout. Paste a video URL into Downloads. *Expect:* Agents shows today's Claude Code and Codex use; the download reaches 100%; auto-wallpaper rotates every 30 min on AC. (#170)
- [ ] **D26** Optional, with an n8n server: store the key with `secret-tool store --label='n8n API key' service subcult-n8n` and set the URL in the n8n panel. *Expect:* active workflows and recent failures show.

### Launcher

- [ ] **D27** Press Super+Space, read the placeholder, then search for an app and press Enter. *Expect:* "Search   = calc  @ web  . files  : emoji  $ clipboard" fits in the box; favourites come first; long descriptions end in "…" inside the box; the app starts. (#145)
- [ ] **D28** Try `=2^10`, `5 km to mi`, `@yt cats`, `@gh subarchy`, `.notes`, `:fire` and `$`, then `font set Iosevka`, `system reboot` (then Escape) and `lock`. *Expect:* answers are copied on Enter, searches open the browser, files and emoji work, and `$` lists clipboard history. Commands run in a terminal; reboot asks first; `lock` opens no terminal.
- [ ] **D29** Type a question and pick "Ask <agent>". *Expect:* the row warns that the text leaves the machine; the Claude Code answer shows in the preview and Enter copies it.
- [ ] **D30** Create `~/.config/subcult/launcher/aliases.json`, `snippets.json` and a script in `~/.config/subcult/commands/`, and use each. Then run `quickshell ipc -p /usr/share/subcult/shell call subcult.launcher clearHistory`. *Expect:* the alias comes first and passes arguments; the snippet fills `{date}` and `{clipboard}`; the script asks for missing arguments; the history resets.

### Alt-Tab, clipboard, polkit

- [ ] **D31** Hold Alt and tap Tab and Shift+Tab, with windows on several workspaces; repeat with Right Alt, and again right after `systemctl --user restart subcult-shell` restarts the shell. *Expect:* cards with icons, most recent first; releasing either Alt focuses the choice; a quick tap goes to the previous window, also on the first Alt-Tab after the restart. (#113, #169)
- [ ] **D32** Copy text and an image, press Super+Ctrl+V and pick an older entry; copy a password from Proton Pass; run `subcult clipboard copy`, `list` and `clear`. *Expect:* history newest first; the password is not stored and clears after 30 s; `copy` returns at once. (#112)
- [ ] **D33** (new) Run `pkexec true`, type a wrong password, then the right one without clicking. Run it again, click elsewhere in the dialog, and press Escape. *Expect:* a retry message with focus kept in the field; the right password works with no click; Escape cancels. Post the result on #85. (#85, #169)

## 5 Lock, idle, suspend, lid, fingerprint

- [ ] **K1** (retest) Run `subcult lock` on AC with motion on, then on battery. Move the mouse over the clock, press a key, enter a wrong password, then the right one. *Expect:* the loop plays centred, with no flash of the final still first; on battery a still shows. No pointer over the clock. The wrong password is refused and the right one unlocks. (#145, #164)
- [ ] **K2** (retest) At the lock, type a wrong password 3 times, then up to 10. Wait 2 minutes and unlock. *Expect:* 3 failures do not lock the account; after 10 the lock shows faillock's text with the time left; after 2 minutes the right password unlocks without a hard reset. (#119, #147)
- [ ] **K3** While locked, switch to Ctrl+Alt+F3 and back, then click or press Tab. *Expect:* the field takes input again.
- [ ] **K4** While locked, run `pkill -KILL -f subcult/lock` from another TTY. *Expect:* the session stays locked and a new prompt appears within about 1 s. If it does not come back, run R6. (ADR 0070, #108)
- [ ] **K5** Run `subcult idle`, then leave the machine alone. Change the Idle settings, run `subcult idle apply` and `subcult idle config`. *Expect:* lock at 7, display off at 10, suspend at 15 minutes, in that order; input wakes the display; the config shows the new times and `inhibit_sleep = 3`.
- [ ] **K6** Undocked on battery, close the lid for 30 s, open it, and unlock. *Expect:* the lock is visible before sleep, with no black display or warning flash; Wi-Fi and Bluetooth come back by themselves.
- [ ] **K7** (new) Suspend with `subcult system suspend` from the launcher or power menu, resume, unlock, docked and undocked. *Expect:* the lock shows before sleep; the lock unit ends without restarts; Wi-Fi and dock Ethernet come back within a few seconds. Network recovery after resume has never been checked. (#101, #110, Gitea #240)
- [ ] **K8** From the launcher, run `system logout`, then `system reboot` and `system shutdown` on later passes. *Expect:* each asks first, opens no terminal and does what it says. (#110)
- [ ] **K9** Press the power button briefly at the desktop and at the lock screen, then hold it. Separately, run `systemctl poweroff` while locked. *Expect:* a short press locks and never powers off; a long press powers off; the desktop never shows while a locked session shuts down. (#132, #136)
- [ ] **K10** (new) Run `subcult setup fingerprint` as yourself, not with sudo, and enroll a finger. *Expect:* it asks for sudo itself when it installs fprintd and when it enrolls; the finger is enrolled and verified. Without a supported reader it says so ("no fingerprint reader found" or "fprintd finds no reader it can use") and the lock stays password-only. Run with sudo, it refuses: "run it as yourself, not with sudo". (#93, #151)
- [ ] **K11** (new) Lock, touch the reader, try a wrong finger, and press Escape while a check waits. Unlock by password once. Suspend, resume, and try the reader again. *Expect:* "Or touch the fingerprint reader" shows; a touch unlocks; a wrong finger says it is not recognised and the password still works; Escape brings back the prompt; the reader works after resume. (#151)
- [ ] **K12** (new) Run `subcult setup fingerprint remove` (it asks for sudo itself) and lock. *Expect:* no fingerprint line; only the password unlocks; sudo and polkit asked for the password throughout.

## 6 Power, battery, NVIDIA

- [ ] **P1** Unplug and replug the charger and run `powerprofilesctl get` after each. Pick a profile by hand. *Expect:* power-saver on battery and balanced on AC; the bar label follows; a hand-picked profile holds until the next plug change. (#100)
- [ ] **P2** In the battery panel, change Battery display and Power profile, restart the shell, and right-click the widget. *Expect:* the choices persist; right-click cycles Quiet, Cool, Balanced and Performance.
- [ ] **P3** (retest) After a fresh boot, open the charging controls and run `subcult dell power state`. *Expect:* Custom shows with start 50% and stop 85% unchanged; `subcult-dell-power-permissions.service` succeeded. (#107)
- [ ] **P4** Run on battery past 20% and then 10%. *Expect:* one "low" and one "critical" notification, each once per crossing.
- [ ] **P5** Run `subcult thermal zones`, load the CPU (`stress-ng --cpu 0`), then kill the thermal watch process. *Expect:* zones and trips are listed; one notification per hot excursion; the watch restarts after 30 s. (#161, #177)
- [ ] **P6** Set motion to auto, unplug, then replug. *Expect:* on battery animations, blur and shadows go off and the lock shows a still; on AC they return.
- [ ] **P7** Run `subcult hw info`, `subcult hw fixes`, `subcult hw packages` and `subcult hw services`. *Expect:* Intel CPU, Intel and NVIDIA GPUs, Wi-Fi, Bluetooth and the Dell power fix; packages include sof-firmware and the NVIDIA open DKMS driver. Note which fixes behave, so they can be marked tested. (ADR 0050)
- [ ] **P8** (retest) Run `nvidia-smi` and `subcult gpu mode`, then `subcult gpu run kitty --debug-rendering 2>~/kitty-offload-N.log` 5–10 times. *Expect:* the RTX 3050 Ti is listed; the mode is intel; each window stays mapped, reports NVIDIA OpenGL and exits 0. If one vanishes, note how long it was gone and attach its log to #106.
- [ ] **P9** (new) Undocked on battery in intel mode, run `cat /sys/bus/pci/drivers/nvidia/*/power/runtime_status` (or find the card's address with `lspci -D | grep -i nvidia` and read `/sys/bus/pci/devices/<that address>/power/runtime_status`) and run `sudo fuser -v /dev/nvidia*`. *Expect:* `suspended`, with no Hyprland or quickshell holding the device. (ADR 0006)
- [ ] **P10** Run `subcult gpu mode nvidia` and sign in again, first on battery, then docked on AC with both panels. Run `subcult gpu mode intel` at the end. In each mode, run `nvidia-smi` and check both dock panels. *Expect:* undocked it falls back to intel; docked on AC the NVIDIA desktop drives every output smoothly and `nvidia-smi` lists Hyprland as a process on the card; intel reverts it, and both dock panels light up in either mode. Post date, kernel and result for each mode on #51.

## 7 Displays and dock

- [ ] **M1** Press Super+/ and Super+Alt+/ on the laptop panel, then run `subcult display scale 1.6`. Use the bar, launcher, notifications, panels, lock and greeter, then sign in again. *Expect:* the scale steps through 1, 1.25, 1.6, 2, 3 and 4; at 1.6 nothing is clipped and text is sharp; the wallpaper is sharp; 1.6 survives the new login. (#103)
- [ ] **M2** Plug in the dock with both ONN panels. *Expect:* every monitor lights up (through evdi if the dock is DisplayLink); one bar per monitor, the full bar on the primary and the Minimal bar elsewhere; the wallpaper rotates once. (#166, #171)
- [ ] **M3** Run `subcult display profile save desk`, `profile list`, `profile apply desk --dry-run`. Then force a bad apply: copy `~/.config/subcult/display/profiles.json` aside, change one panel's `"mode"` in it to `"1234x567@60"`, run `subcult display profile apply desk`, and unplug and replug the dock. Put the copy back, then run `profile remove desk` at the end (after M4). *Expect:* list marks the profile as matching; the dry run prints what it would do. The bad apply either prints a `subcult display:` error or Hyprland falls back to a mode the panel offers; either way a usable display remains, `systemctl --user is-active subcult-display` says active, and `journalctl --user -u subcult-display -b` shows the failure reported rather than the service restarting in a loop. Remove forgets the profile. (#166, #171)
- [ ] **M4** Unplug the dock, replug it, then swap the order of the two panels' cables. Note which panel gets the portrait layout. *Expect:* the profile returns by itself with its workspaces; undocked gives the laptop layout; portrait stays on the physically portrait panel. If it moves to the other panel, report it on #98. (#98)
- [ ] **M5** (retest) Docked, close the lid, reopen it, then unplug the dock once with the lid open and once with it closed, and replug. *Expect:* lid closed: externals on, panel off, no suspend. Reopened: the panel's mode, scale and workspaces return. Unplugged: a usable display always remains. Replugged: the saved layout returns. (#103, Gitea #220, Gitea #223)

## 8 Audio, Bluetooth, HT3

- [ ] **A1** Play through the speakers, plug in wired headphones and unplug them, then run `arecord -d 5 /tmp/m.wav && aplay /tmp/m.wav`. *Expect:* output moves to the jack and back; the recording of the internal mic is clear. Note the devices used. (#51)
- [ ] **A2** Using only the Bluetooth panel: right-click the widget to toggle the adapter. Then search, choose "Pair and trust" on a device that is not yet paired, and confirm any PIN in the panel. Cancel one pairing, and right-click a device to forget it. *Expect:* each step works without `bluetoothctl`, and the device connects and plays. (#105)
- [ ] **A3** Play over Bluetooth, suspend, resume; then turn the device off and on. *Expect:* it reconnects by itself and audio continues.
- [ ] **A4** (new) Connect the HT3. Open its panel and compare battery and noise mode with the headphones; change mode on the headphones. Close the panel and run `pgrep -af 'ht3 watch'`. Reopen it while the TOZO app holds the headphones on a phone. Take the address from `bluetoothctl devices | grep -i HT3` and run `subcult ht3 status <that address> --json`. *Expect:* the widget shows only while the HT3 is connected, and only when its Bluetooth name contains both "HT3" and "TOZO" in any case (`bluetoothctl info <address>` shows the name; if it lacks either word, the widget stays hidden by design); readings match and follow within 30 s; the helper has exited; with the app connected the panel says the headphones refused the control channel; the CLI reads once. (#65, #150)
- [ ] **A5** (new) In the HT3 panel, switch Normal, ANC and Transparency, and move the volume bar to the top. *Expect:* each change is audible and shows only after the headphones confirm it; volume moves only the HT3, stops at 100%, and leaves the default output alone. (#153, #181)

## 9 Network, Wi-Fi, Tailscale, Taildrop, LocalSend

- [ ] **N1** In the network panel, join a known and a new network, leave one, right-click to forget one, then reboot. *Expect:* the connected network first, then known ones, then the rest by signal; it reconnects after the reboot. (#60)
- [ ] **N2** Optional: on public Wi-Fi with a captive portal, try to sign in. *Expect:* on main today the portal does not load: ADR 0020's captive-portal exception is not built, and DNS stays on strict DNS-over-TLS (`resolvectl status`). That is the known gap Q25, not a new failure; record the network and result under Q25. If the portal does load, note how.
- [ ] **N3** (new) In the Tailscale panel, choose Sign in, finish in the browser, then click and right-click a peer, pick an exit node, clear it, turn Tailscale off and on, sign out and in. *Expect:* no password prompt; the panel picks up the sign-in by itself. Click copies a peer's address and right-click its DNS name. The local network stays reachable through the exit node. The exit node and local-network setting come back after signing in again. (#157, #171, ADR 0058, ADR 0062)
- [ ] **N4** (new) Send a file with "Send files with Taildrop" and with `subcult tailscale send <peer> ~/file` (list peer names with `tailscale status`); send one to sputnik from another machine; interrupt a transfer of several files. *Expect:* a notification reports each send; received files land in `~/Downloads`; finished files are kept after the interruption. (#157, #171)
- [ ] **N5** Connect Proton VPN with Tailscale up, then disconnect. *Expect:* DNS and the tailnet keep working; disconnecting restores direct DNS-over-TLS.
- [ ] **N6** Send a file to and from a phone with LocalSend. *Expect:* both sides find each other and the transfer completes. (#158)

## 10 Apps and theming

- [ ] **T1** Open from the launcher: kitty, Dolphin (thumbnails), yazi, Ark, Chromium, Signal, Halloy, Obsidian, Okular, swayimg, VLC, qalculate, btop, cliamp, Neovim, OBS, Kdenlive, GIMP, Inkscape, Glaxnimate, qBittorrent. Record 10 s with gpu-screen-recorder. *Expect:* each starts; the recording plays back and the screen mark lights while recording.
- [ ] **T2** Sign in to Proton Mail, Proton Pass (desktop and `pass-cli`), Proton VPN, Proton Authenticator, `proton-drive-cli`, `bw`, Discord (Vencord loads), `claude`, `codex` and `opencode`; run `subcult agent usage`. *Expect:* each signs in; usage shows today's and this week's tokens. (#158, #159, #80)
- [ ] **T3** Run `ls /etc/xdg/mimeapps.list ~/.config/mimeapps.list` and `xdg-open` on a PNG and a PDF; look for Zen, T3 Code, VS Code, pipewire-control-center, disktree and tuxguitar in the launcher; open Print Settings. *Expect:* on main today neither `mimeapps.list` exists, so each file opens in whichever installed app desktop-file-utils lists first; write down which (for example swayimg or GIMP, Okular or Chromium). The six apps are absent and there is no CUPS server. These are known gaps, not failures; they feed Q10.
- [ ] **T4** Run `subcult app list --role browser`, `app show vlc`, `app default`, `app validate`, `app install <small id> --dry-run`, the real install, `app remove <id>`, and `app default browser chromium`. *Expect:* the plan lists packages; install and remove work; `xdg-open` and Super+Shift+B then use Chromium.
- [ ] **T5** Run `subcult app webapp install Example https://example.com`, launch and remove it. Then run `subcult app webapp install "Google Maps" maps.google.com` (a bare host), launch it, check its class with `hyprctl clients`, and remove it with `subcult app webapp remove "Google Maps"`. *Expect:* each is an app window with its own launcher entry and icon; the Maps window class is `chrome-maps.google.com__-Default`; remove takes the launcher entry away. (#112)
- [ ] **T6** Run `subcult docker tui`, then `docker run --rm -p 8080:80 nginx` and probe port 8080 from another LAN host; then run `sudo subcult docker sudoless`. *Expect:* lazydocker reaches Docker after a polkit prompt; the port is blocked from the LAN; sudoless warns that it equals passwordless root and asks first. (ADR 0055)
- [ ] **T7** In a new kitty, check the prompt, Ctrl-R, `z <dir>`, Ctrl-T, `y`, `ga`, `gd`, `tdl`, and Tab after `subcult `; run `subcult shell set bash`, sign out and in, then `subcult shell set zsh` and sign out and in again. *Expect:* Starship, atuin, zoxide, fzf keys, yazi cd-on-exit and completion all work; each change of login shell takes effect at the next login (`echo $SHELL` in a new kitty), not in terminals already open.
- [ ] **T8** Run `pult doctor`, then `pult apply -yes <another theme>`, then `pult apply -yes -profile /usr/share/subcult/default/theme/subarchy.toml`. Open Okular, Ark, VLC and a GTK file picker. *Expect:* the shell, Hyprland borders, kitty and Neovim recolour live and the next lock uses the palette; kitty's cursor stays white; Okular, Ark and VLC use Pult colours; GTK uses adw-gtk3-dark. (#152, #173, ADR 0037)
- [ ] **T9** Run `subcult theme apply-system`, accept the prompt, and reboot. *Expect:* SDDM, Plymouth (label and error line too) and the Limine menu use the palette. (#79)
- [ ] **T10** Run `subcult cursor set --role green --size 32`, then `subcult cursor apply` after a theme change, then `subcult cursor set --role lavender --size 24` to go back to the default. *Expect:* the cursor changes colour and size in Hyprland, GTK and Qt apps, and the last command restores the lavender 24 px default.
- [ ] **T11** Run `subcult font list`, `font current`, `sudo subcult font set "JetBrainsMono Nerd Font"`, `font check <family>`, `font import ~/x.otf`, and set a Monaspice family other than Ne. *Expect:* installed Nerd Font families are marked; set changes the terminal and shell font; check warns about missing glyphs; the other Monaspice applies. (#175)

## 11 subcult commands, update, channel, snapshots

- [ ] **C1** Run `subcult --help`, `subcult --version`, `subcult commands`, `subcult commands --json --all` and `sub commands`; press Tab after `subcult ` in zsh and bash. *Expect:* every route listed with a summary; `sub` is an alias; completion offers groups and actions.
- [ ] **C2** (new) Run the theme commands the site's docs page shows: `pult apply catppuccin-mocha`, `pult apply -profile /usr/share/subcult/default/theme/subarchy.toml`, `subcult theme apply-system` and `subcult cursor apply`. *Expect:* each command exists and does what the page says; none gives an unknown-command error. (#185)
- [ ] **C3** On the old install, before reinstalling: run `subcult update`, then check `rd.luks.options` in `/etc/kernel/cmdline` and `KERNEL_CMDLINE` in `/etc/default/limine`. Run the update again, then reboot. *Expect:* `,tries=0` is added once to each; the second run changes nothing; the passphrase prompt asks without limit. (#144, migrations/1794532900.sh)
- [ ] **C4** On the old install: run `subcult update migrate` twice and list `~/.config/subcult/theme/`. *Expect:* the subarchy-shell and subarchy-hyprland target files appear for the active theme; the second run does nothing. (#122)
- [ ] **C5** (retest) When a new core package is published, run `subcult update --dry-run`, then `subcult update`, then `hyprctl binds | wc -l`. *Expect:* one password prompt at the start and no second one. No red Hyprland banner about `default/hypr/bootstrap.lua`. Hyprland reloads at the end with about 52 binds, scale keys included. The update count drops to the true remainder. A kernel change gives a reboot notice. When an upgraded package's files are still in use, the summary ends with "Services using replaced files: … Restart them, or reboot.", user services marked "(user)", and nothing is restarted for you. fwupd's "nothing to do" is not a failure. (#109, ADR 0069, #161, Gitea #139)
- [ ] **C6** Run `subcult update check`, `subcult update migrate --pending` and `systemctl --user list-timers subcult-update-check.timer`. *Expect:* a count (exit 2 for none), no pending migrations after a full update, and a daily timer that installs nothing.
- [ ] **C7** Run `sudo snapper -c root list` after an update. *Expect:* pre and post snapshots, at most 5 numbered ones, matching Limine's Snapshots menu. (ADR 0011)
- [ ] **C8** Run `subcult channel`, `sudo subcult channel set edge`, `subcult update --dry-run`, `sudo subcult channel set stable`. *Expect:* stable on snapshot 2026/11/12; edge uses the live mirrors; stable restores the snapshot mirrorlist. (ADR 0026)

## 12 Recovery

- [ ] **R1** Boot a Snapshots entry from Limine and look at the desktop. Only with your approval, since it replaces the root: run `sudo limine-snapper-sync --restore`. *Expect:* the snapshot boots read-only with a writable overlay; restore keeps a "backup before restore" snapshot and reboots into the restored root. (ADR 0011)
- [ ] **R2** Run `pkill -KILL -f subcult/shell`, then `systemctl --user mask subcult-shell` and unmask it. *Expect:* the bar returns within seconds without ending or unlocking the session; mask keeps it off.
- [ ] **R3** If Hyprland shows its emergency banner, run `hyprctl reload`. *Expect:* the normal binds return and `hyprctl configerrors` is empty.
- [ ] **R4** Press F12 and boot Omarchy's entry. Both entries read "Limine"; Omarchy's is the one whose partition GUID in `efibootmgr -v` is the Crucial ESP's (on Subarchy, `lsblk -o NAME,MODEL,PARTUUID` shows which ESP is on the Crucial disk). *Expect:* Omarchy boots from the Crucial disk, untouched.
- [ ] **R5** After 10 wrong passwords, run `faillock --user <your user name> --reset` from a root shell opened before the failed attempts (for example `sudo -s` in a terminal; sudo may refuse your password while the account is locked). `id -un` in your own session prints the name. *Expect:* sign-in works at once.
- [ ] **R6** If the lock prompt does not come back (K4), from Ctrl+Alt+F3 run `journalctl --user -b -u subcult-lock`, `systemctl --user reset-failed subcult-lock` and `systemctl --user start subcult-lock`. *Expect:* the prompt returns and still needs the password. (ADR 0070)
- [ ] **R7** Check that `@factory` exists (`sudo btrfs subvolume list /`). *Expect:* it exists; there is no factory-reset command yet (Q18).

## 13 Decisions for the owner

Each one needs an answer, recorded on the issue or ADR named. IDs stay
stable: Q17, Q23 and Q24 were settled by #185, #184 and #183.

- [ ] **Q1** (decision) Secure Boot key custody and recovery, and the TPM PCR policy and recovery, before F12 and F13. (ADR 0010, ADR 0012, #51)
- [ ] **Q2** (decision) Rename the firmware entries from "Limine" to "Subarchy", and keep or drop Omarchy's entry. (#140)
- [ ] **Q3** (decision) Whether online installs stay on the stable snapshot and the live root follows it, so the installed kernel is never older than the stick's. (ADR 0049)
- [ ] **Q4** (decision) Installer: offer to unlock a LUKS partition read-only while browsing; support installing beside another OS (reuse its EFI partition or add one, minimum free space, Limine chainload; changes ADR 0009); keep the visible 2 s boot menu with a beep and the static mark. (#124, #143)
- [ ] **Q5** (decision) If I13 or I14 look faint by eye: pad the focused button, or draw the progress track in a muted colour.
- [ ] **Q6** (decision) The 1.5 s of black before the shutdown splash, and whether to hide its progress bar; a sign once the lock's password passes 16 characters.
- [ ] **Q7** (decision) HT3 panel controls: noise mode, HT3-only volume, EQ. #181 added the first two; EQ is left. (#153)
- [ ] **Q8** (decision) Confirm or change the Tailscale policy (active session connects, signs in, picks exit nodes and sends files without a password) and the starting list of actions that skip sudo or polkit. (ADR 0062)
- [ ] **Q9** (decision) Ship a screenshot key; bind or autostart voxtype dictation. (ADR 0056)
- [ ] **Q10** (decision) Default apps: ship `/etc/xdg/mimeapps.list` or run `subcult app default` at install; vendor or unmark the six missing "preinstalled" apps; add CUPS per ADR 0022 or change the ADR; the 1010-package budget. (#168, #172, ADR 0054)
- [ ] **Q11** (decision) Finish the app list review: overlaps (Bitwarden CLI and Proton Pass, browsers, PDF, archive), sputnik apps left out, more web apps, chatgpt-desktop. Then set [[app-list]] to `review: done`. (ADR 0044)
- [ ] **Q12** (decision) Cursor colour: kitty's Subcult Ink cursor now uses the palette's #FFFFFF (#173). Confirm it or ask for #00FF88, and say whether Subcult Ink stays a separate scheme. (#4)
- [ ] **Q13** (decision) Sign a Pult release with pult#34 so Dolphin follows catalog themes, and bump `packaging/pult`. (#77)
- [ ] **Q14** (decision) Approve the 25 upscaled wallpapers in `~/Pictures/subcult-wallpapers-4k/` and decide on the other 84. (ADR 0038)
- [ ] **Q15** (decision) Switch the installer, boot, greeter and lock from the SUBCULT mark to the Subarchy identity; where `Documentation=`, polkit `vendor_url` and PKGBUILD `url=` should point. (ADR 0052, #178)
- [ ] **Q16** (decision) Restic backup target: a repository on Dozor over SFTP. (ADR 0060)
- [ ] **Q18** (decision) Build a factory-reset command with a keep-home mode. (ADR 0056)
- [ ] **Q19** (decision) Signing key: confirm the second copy exists and whether a rotation procedure is wanted, then update ADR 0025. (#87)
- [ ] **Q20** (decision) Licence gate: SUBCULT assets under `ASSETS_LICENSE.md`, origin headers on borrowed files, redistribution of displaylink and nvidia-580xx. (ADR 0053, #84)
- [ ] **Q21** (decision) After the #51 results are in: review the release notes' tested-hardware list and tag the first release on stable. (ADR 0066, #84)
- [ ] **Q22** (decision) The black gap before the Plymouth prompt (F2): once F2 shows the cause, choose a fix, for example leaving the NVIDIA modules out of the initrd or booting with `plymouth.use-simpledrm`. No issue tracks it yet.
- [ ] **Q25** (decision) Whether captive-portal sign-in (ADR 0020's exception, not built) must work for the first release (N2).

## 14 Other hardware (optional)

These need hardware or accounts other than sputnik's. Run them when such a machine is at hand; they do not block the first release.

- [ ] **O1** (new) On a desktop with both an Intel and an NVIDIA GPU where every connected monitor hangs off the NVIDIA card, sign in with `subcult gpu mode` set to intel. *Expect:* the session starts in NVIDIA mode anyway and every monitor shows the desktop. (#113)
- [ ] **O2** (new) On a machine with no backlight (a desktop with an external monitor), press the brightness keys. *Expect:* nothing changes and no LED (keyboard or Caps Lock) changes brightness. (#169)
- [ ] **O3** (new) On a system with two or more users in `wheel`, run `pkexec true` as one of them. *Expect:* the polkit dialog names the current user, never another admin or a group. (#169)
- [ ] **O4** Google calendar is not built yet (#89); there is nothing to test until it is.

Related: [[first-install]] · [[review-index]] · [[app-list]] · [[0049-installer|ADR 0049]] · [[0050-hardware-support|ADR 0050]]
