---
title: "ADR 0050: Hardware support policy"
type: decision
status: accepted
adr: 50
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, delivery, hardware]
aliases: [ADR 0050, R3, Hardware support]
---

# ADR 0050: Hardware support policy

Decision map item R3. Accepted 2026-11-06.

## Decision

**Port all of Omarchy's x86_64 hardware fixes** from the start, applied by
detection at install and re-checked by a hardware command afterwards.
Fixes for aarch64 machines are not ported
([[0003-cpu-architectures|ADR 0003]]).

## Scope from Omarchy 4.5 `install/hardware/`

| Vendor or area | Fixes |
|---|---|
| Apple (Intel, T2) | `fix-t2`, `fix-spi-keyboard`, `fix-suspend-nvme`, `fix-brcmfmac-supplicant` |
| ASUS | ROG (`asus-rog.sh`), ProArt P14 speakers, ExpertBook B9406 display, touchpad and backlight, Z13 touchpad |
| Dell | XPS 13 PTL speaker firmware, XPS 13 sidecar amps, XPS touchpad haptics |
| Framework | Framework 16, QMK HID |
| Intel | Wi-Fi 7 EHT, FRED, IPU7 camera, LPMD, SOF firmware, thermald, video acceleration |
| Lenovo | Yoga Pro 7 bass speakers |
| Microsoft | Surface, Surface keyboard |
| Tuxedo | Keyboard backlight |
| Peripherals | Elgato Cam Link 4K, Motorcomm YT6801 Ethernet, Broadcom BCM43xx, Synaptics touchpad, function keys |
| General | Bluetooth, network, NVIDIA, Vulkan, speaker tuning, wireless regulatory domain |

Not ported: `nvidia/dgx-spark-boot.sh`, `gb10/`, `n1x.sh`, `qualcomm/`, and
the Lenovo Yoga Slim 7x scripts, which target aarch64 machines. Check each
remaining script's target before porting; a few may also be aarch64-only.

Omarchy's 42 `omarchy hw` detection and matching commands (`hw match`,
`hw laptop`, `hw hybrid gpu`, `hw vm` and others) are the detection layer to
port with them.

## Options considered

| Option | Why not chosen |
|---|---|
| Tested tier with best-effort ports | Narrower; the owner wants broad support from the start. |
| Owner's machines only | Not a public distribution. |

## Consequences

- Most of these fixes cannot be tested without the hardware. Each port is
  marked **untested** until someone runs it on the machine; release notes
  list the tested set.
- Each fix keeps a link to its Omarchy source and version so later Omarchy
  fixes can be compared.
- Vendor add-ons such as Dell power profiles
  ([[0021-power|ADR 0021]]) follow the same detection.

## Progress

- 2026-11-07: `subcult hw` answers the matching questions the fixes ask
  (issue #66): `subcult hw <question>` exits 0 for yes, `hw match <text>`
  matches the product name or family, `hw matches` lists every answer, all
  from sysfs, `/proc` and udev data under a root directory, so fixtures
  stand in for machines in the tests. The questions follow Omarchy 4.5.0's
  `omarchy-hw-*` commands as behaviour and name their source; `hw vm` reads
  DMI and the CPU's hypervisor flag instead of `systemd-detect-virt`,
  `hw hybrid-gpu` does not ask supergfxctl, `hw touchpad` and
  `hw touchscreen` read input names and udev tags instead of `hyprctl`, and
  `hw laptop-closed` reads the ACPI lid only. Not ported: `intel-ptl` (lspci
  text; needs PCI ids) and so `dell-xps-oled`, the `aarch64` board
  variants beyond Apple, and the platform `displays.conf` lists.
- 2026-11-08: the Intel and general fixes (issue #81). `internal/hw/fixes.go`
  is the catalogue: each fix names its Omarchy 4.5.0 source, whether it has
  run on real hardware (none yet beyond what the VM exercises), the packages
  and services it adds (which `hw packages` and `hw services` carry) and
  the files it writes (modprobe options, initramfs modules, kernel command
  line drop-ins). `subcult hw fixes` lists the machine's, `--all` the
  catalogue, `subcult hw apply` writes the files, and the installer runs it
  on the target before pacstrap so the UKIs carry them. Ported: Wi-Fi 7
  EHT off on the two Intel radios that need it, FRED on Panther Lake,
  intel-lpmd on the Intel laptops Omarchy lists, Intel video acceleration
  (libvpl, vpl-gpu-rt beside the media driver), NVIDIA modeset and initramfs
  modules, the Apple function-key row for every x86 keyboard, and the
  wireless regulatory domain from the time zone (in the installer). The
  IPU7 camera fix is listed with a note: `intel-ipu7-camera` is not in
  Arch's repositories and needs packaging first. Bluetooth and
  NetworkManager were already enabled; thermald and SOF firmware were
  already chosen. Fixtures cover a Panther Lake laptop, an NVIDIA desktop
  and the VM.
- 2026-11-07: DisplayLink (issue #107): `evdi-dkms` and `displaylink` are
  vendored under `packaging/aur/`; with a `17e9` USB adapter present,
  `subcult hw packages` adds them (and the kernel headers DKMS needs),
  `subcult hw services` lists `displaylink`, and the installer enables it.
  The DKMS check after an update already covers evdi, being generic.

Related: [[decision-map|Decision map]] · [[0005-firmware|ADR 0005]] · [[0006-gpu-drivers|ADR 0006]] · [[0049-installer|ADR 0049]]
