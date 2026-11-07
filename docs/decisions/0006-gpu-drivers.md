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
- **Hybrid laptops**: the integrated GPU draws the desktop. The NVIDIA GPU
  powers off when idle (runtime D3, fine-grained) and runs apps on request:
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

## Options considered

| Option | Why not chosen |
|---|---|
| Open NVIDIA modules only | Leaves GTX 900/10-series owners on nouveau. |
| Nouveau and NVK only | No CUDA or NVENC, much worse laptop power use. |
| NVIDIA renders everything on hybrid laptops | Keeps the discrete GPU powered: shorter battery life, more heat. |
| iGPU only on hybrid laptops | The NVIDIA GPU is unusable until changed. |
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
