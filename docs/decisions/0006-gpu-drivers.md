---
title: "ADR 0006: GPU drivers"
type: decision
status: accepted
adr: 6
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, foundation, gpu]
aliases: [ADR 0006, F5, GPU drivers]
---

# ADR 0006: GPU drivers

Decision map item F5. Accepted 2026-11-06.

## Decision

- **Intel and AMD**: Mesa with Vulkan (`vulkan-intel`, `vulkan-radeon`) and
  VA-API video decode (`intel-media-driver` on Intel), installed by detection.
- **NVIDIA, RTX 20-series and newer**: `nvidia-open-dkms` with `nvidia-utils`
  and `libva-nvidia-driver`.
- **NVIDIA, GTX 900 and 10-series**: `nvidia-580xx-dkms` with
  `nvidia-580xx-utils`, chosen by detection. Arch does not carry this branch;
  Omarchy rebuilds it in its repository, so Subarchy must too (P1).
- **Hybrid laptops**: the integrated GPU draws the desktop by default (Intel
  mode below). The NVIDIA GPU powers off when idle (runtime D3, fine-grained)
  and runs apps on request:
  - a per-app launcher (from `~/.local/bin/gpu-run` on `sputnik`) that sets
    PRIME render offload variables;
  - a session-wide toggle (from `~/.local/bin/gpu-mode`) that writes the same
    variables into the compositor environment for newly launched apps.
- **32-bit graphics libraries** (`lib32-mesa`, `lib32-vulkan-*`,
  `lib32-nvidia-utils`) install **on demand**, when Steam, Wine or Lutris is
  installed. The `multilib` repository stays enabled. The full Intel, AMD and
  NVIDIA set is about 58 packages and 990 MB.

  Revised 2026-11-06 under [[0054-lightweight-battery-first|ADR 0054]]; the
  owner had first chosen to install them on every machine.

## Hybrid laptops: GPU modes (revised 2026-11-07)

Two modes for the whole session. Hyprland chooses its rendering GPU when the
session starts, so changing mode takes a logout and login.

| Mode | Default when | Hyprland renders on | Apps render on | NVIDIA |
|---|---|---|---|---|
| **Intel** | Always, unless the user chose NVIDIA | Intel only (`AQ_DRM_DEVICES` lists the Intel card) | Intel: Mesa EGL (`__EGL_VENDOR_LIBRARY_FILENAMES` set to Mesa's `50_mesa.json`) and Intel Vulkan (`VK_DRIVER_FILES`); `gpu-run` offloads one app to NVIDIA | Powered off (runtime D3) unless an app is offloaded |
| **NVIDIA** | Only after the user accepts the prompt | NVIDIA first, Intel second (Intel still owns the display outputs) | NVIDIA | On |

**Switching is never automatic.** When the laptop is on AC with two or more
external monitors (DisplayLink counts) and the session is in Intel mode, a
notification asks: "Switch the desktop to NVIDIA? Takes effect after you log
out", with Log out now, Later and Not on this dock. When undocked or on
battery in NVIDIA mode, a notification offers the switch back the same way.

At login, an accepted NVIDIA choice applies only if the machine is still on
AC with two or more external monitors; otherwise the session starts in Intel
mode ([[0054-lightweight-battery-first|ADR 0054]]). This login fallback is an
agent proposal; change it if NVIDIA mode should stick regardless.

Implementation notes:

- Device paths for `AQ_DRM_DEVICES` come from udev symlinks (for example
  `/dev/dri/subcult-igpu`, `/dev/dri/subcult-dgpu`), because the stable
  `/dev/dri/by-path/pci-…` names contain colons, which `AQ_DRM_DEVICES` uses
  as its separator, and `cardN` numbers can change between boots.
- The mode is chosen by a session environment generator before Hyprland
  starts ([[0031-session-manager|ADR 0031]]), not in shell startup files.
- Omarchy's `default/hypr/nvidia.lua` (`NVD_BACKEND`, `LIBVA_DRIVER_NAME`,
  `__GLX_VENDOR_LIBRARY_NAME` by GSP and display role) applies in NVIDIA mode.

### Evidence from `sputnik` (2026-11-07)

- Every display connector (`eDP-1`, `DP-1` to `DP-4`, `HDMI-A-1`) belongs
  to the Intel GPU (`card2`, `i915`). The NVIDIA GPU (`card1`) has none; it
  can only render for others.
- Undocked, with only the laptop panel on, the NVIDIA GPU was **awake**:
  runtime status `active`, P8, about **3.6 W**. `Hyprland`, `quickshell` and
  `voxtype-osd-gtk` held `/dev/nvidia*` open.
- Causes: no `AQ_DRM_DEVICES`, so Hyprland opens every GPU; and glvnd tries
  NVIDIA's EGL first (`10_nvidia.json` sorts before `50_mesa.json`), so EGL
  apps open the NVIDIA device even when they draw on Intel.
- Intel mode is meant to fix this. Not yet verified: that NVIDIA reaches D3
  in Intel mode, and that NVIDIA mode drives the Intel outputs smoothly
  (Hyprland multi-GPU copy). Both need a test session on `sputnik`.

## Options considered

| Option | Why not chosen |
|---|---|
| Open NVIDIA modules only | Leaves GTX 900/10-series owners on nouveau. |
| Nouveau and NVK only | No CUDA or NVENC, much worse laptop power use. |
| NVIDIA renders everything on hybrid laptops | Keeps the discrete GPU powered: shorter battery life, more heat. |
| iGPU only on hybrid laptops | The NVIDIA GPU is unusable until changed. |
| Apps switch to NVIDIA automatically when docked | The owner preferred moving the whole desktop. |
| Switch modes automatically on dock and power changes | The owner wants to be asked. |
| 32-bit libraries on every install | First choice; reversed for ADR 0054 because it adds about 1 GB to every machine. |

## Borrowed

- Omarchy 4.5 `install/hardware/nvidia.sh`: detection of the GPU generation
  and the open versus 580xx package choice.
- Owner scripts on `sputnik`: `gpu-run`, `gpu-mode`. Their Hyprland-specific
  toggle file (`~/.local/state/omarchy/toggles/hypr/gpu-everything.conf`)
  changes with the compositor decision (L4).

## Consequences

- DKMS builds both NVIDIA modules for `linux-zen` and `linux-lts` on each
  kernel update ([[0004-kernel|ADR 0004]]). A failed build must block the
  update or keep the previous kernel bootable (P3, B5).
- Runtime D3 is on by default with the open driver on `sputnik`'s Ampere GPU
  (`Runtime D3 status: Enabled (fine-grained)`); the only NVIDIA module option
  set there is `nvidia_drm modeset=1`. Older GPUs may need
  `NVreg_DynamicPowerManagement`; check per generation when implementing.
- The `nvidia-580xx` branch has a finite support life; R3 must say what
  happens when NVIDIA drops it.

Related: [[decision-map|Decision map]] · [[0004-kernel|ADR 0004]] · [[0005-firmware|ADR 0005]]
