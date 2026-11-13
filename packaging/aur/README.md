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
| `nvidia-580xx-utils` | 580.196.07-2 (AUR: -1; see the PKGBUILD) | `0b45a070` | the 580xx driver branch for Maxwell to Pascal GPUs (ADR 0006): `nvidia-580xx-utils`, `nvidia-580xx-dkms` and `opencl-nvidia-580xx` from NVIDIA's `.run` installer, sha256-pinned, with the AUR's two kernel patches |
| `lib32-nvidia-580xx-utils` | 580.196.07-1 | `489271ac` | the 32-bit libraries of the same branch (Steam, Wine): `lib32-nvidia-580xx-utils` and `lib32-opencl-nvidia-580xx` |
| `cliamp` | 2.4.1-1 | `544da13c` | the terminal music player (app list); Go build from the GitHub tag |
| `localsend-bin` | 1.18.2-2 | `f35ec0d6` | LocalSend file sharing (ADR 0056); upstream's `.deb`, Apache-2.0. `fuse2` dropped from depends: it is for the AppImage |
| `voxtype-bin` | 1.2.1-1 | `eb385fd6` | dictation (ADR 0056); upstream's binaries, MIT. Built with the baseline, avx2, avx512 and vulkan variants whatever the build machine; no ONNX or CUDA variants (see the PKGBUILD) |
| `ttfx` | 0.5.1-1 | `67da1790` | terminal text effects, the source of the screensaver loops (ADR 0036; the package plays recorded loops and never runs ttfx); Rust build from the GitHub tag, MIT |
| `proton-mail-bin` | 1.16.1-1 | `14d40f78` | Proton Mail and Calendar (app list); Proton's `.deb` run on Arch's `electron43`, GPL-3.0-or-later |
| `proton-pass-cli` | 2.7.0-1 | `124cbe9a` | the Proton Pass command line (`pass-cli`); Rust build from the Git tag, b2sum-pinned, GPL-3.0-or-later. No debug package: with the AUR's debug info it is 145 MB |
| `proton-authenticator-bin` | 1.1.6-1 | `560b882a` | Proton Authenticator; Proton's `.deb`, GPL-3.0-or-later |
| `proton-drive-cli-bin` | 0.9.0-2 | `ad340ebd` | the Proton Drive command line (`proton-drive`); Proton's binary, MIT |

The Limine tools build a native binary with GraalVM (downloaded by the
PKGBUILD, sha256-pinned) and Gradle. The NVIDIA pair download the 400 MB
`.run` file from download.nvidia.com; their licence is NVIDIA's (`custom`).

`cliamp` and `proton-pass-cli` also list the C libraries they link against
as makedepends: `build.sh` and CI install only makedepends (`makepkg
--nodeps`). Proton VPN (`proton-vpn-gtk-app`, `proton-vpn-cli`) comes
from Arch's `extra` and is not rebuilt here.

`claude-code` (154 MB) and `proton-pass-bin` (145 MB, with its own
Electron) are over the 100 MB the registry's public route accepts, like
`nvidia-580xx-utils`. A PKGBUILD here is built and published by CI and
fetched by the ISO build, so they are added only once their files are in
both channels through the origin
([package publishing](../../docs/package-publishing.md)).

`proton-mail-bin` runs on Arch's Electron, as the AUR package does.
Electron then reports an unpackaged app, so Proton Mail takes its
development path: the window is titled "Proton Mail Dev", Sentry logs in
debug mode, and it skips its certificate pinning for Proton's hosts
(Chromium's normal TLS checks still apply). Proton's own Electron would
put the package over 100 MB too.

```bash
packaging/aur/build.sh limine-mkinitcpio-hook limine-snapper-sync
```

builds each one in a fresh `archlinux:latest` container and adds the result
to `build/repo`, the local unsigned repository the ISO and install tests use.
To update a package, review the new AUR PKGBUILD diff, copy it here and
update this table.
