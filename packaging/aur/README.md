# packaging/aur

AUR packages Subarchy ships, rebuilt into its own repository
([ADR 0025](../../docs/decisions/0025-package-repository.md)). Each directory
holds the PKGBUILD as reviewed. Upstream sources are pinned by tag and
sha256 in the PKGBUILD.

| Package | Version | AUR commit | Needed by |
|---|---|---|---|
| `limine-mkinitcpio-hook` | 1.40.0-1 | `94ffde9c` | UKIs and Limine entries (ADR 0007, 0008) |
| `limine-snapper-sync` | 1.32.1-1 | `b3c82ade` | snapshot boot entries (ADR 0011) |
| `evdi-dkms` | 1.15.1-1 | `9f1f2b56` | the DisplayLink kernel module, built by DKMS (ADR 0050; `subcult hw packages` adds it for a `17e9` USB adapter) |
| `displaylink` | 6.4-1 | `8b49499d` | the DisplayLink manager from Synaptics' Ubuntu driver (custom EULA plus GPL2 and LGPL2.1 parts); `displaylink.service` is enabled at install when the adapter is present |

| `yay` | 13.1.0-1 | `a856562d` | the AUR helper `subcult update` runs (`yay -Sua`); Go build from the GitHub tag |
| `tzupdate` | 3.1.0-1 | `1b3c3bdf` | time zone from the network's location (ADR 0025 list); Rust build from the GitHub tag |
| `ufw-docker` | 251123-1 | `76e18ac8` | Docker behind ufw (ADR 0025 list); a shell script from the GitHub tag, b2sum-pinned |
| `nvidia-580xx-utils` | 580.196.07-1 | `0b45a070` | the 580xx driver branch for Maxwell to Pascal GPUs (ADR 0006): `nvidia-580xx-utils`, `nvidia-580xx-dkms` and `opencl-nvidia-580xx` from NVIDIA's `.run` installer, sha256-pinned, with the AUR's two kernel patches |
| `lib32-nvidia-580xx-utils` | 580.196.07-1 | `489271ac` | the 32-bit libraries of the same branch (Steam, Wine): `lib32-nvidia-580xx-utils` and `lib32-opencl-nvidia-580xx` |

The Limine tools build a native binary with GraalVM (downloaded by the
PKGBUILD, sha256-pinned) and Gradle. The NVIDIA pair download the 400 MB
`.run` file from download.nvidia.com; their licence is NVIDIA's (`custom`).

```bash
packaging/aur/build.sh limine-mkinitcpio-hook limine-snapper-sync
```

builds each one in a fresh `archlinux:latest` container and adds the result
to `build/repo`, the local unsigned repository the ISO and install tests use.
To update a package, review the new AUR PKGBUILD diff, copy it here and
update this table.
