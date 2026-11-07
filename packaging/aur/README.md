# packaging/aur

AUR packages Subarchy ships, rebuilt into its own repository
([ADR 0025](../../docs/decisions/0025-package-repository.md)). Each directory
holds the PKGBUILD as reviewed. Upstream sources are pinned by tag and
sha256 in the PKGBUILD.

| Package | Version | AUR commit | Needed by |
|---|---|---|---|
| `limine-mkinitcpio-hook` | 1.40.0-1 | `94ffde9c` | UKIs and Limine entries (ADR 0007, 0008) |
| `limine-snapper-sync` | 1.32.1-1 | `b3c82ade` | snapshot boot entries (ADR 0011) |

Both build a native binary with GraalVM (downloaded by the PKGBUILD,
sha256-pinned) and Gradle.

```bash
packaging/aur/build.sh limine-mkinitcpio-hook limine-snapper-sync
```

builds each one in a fresh `archlinux:latest` container and adds the result
to `build/repo`, the local unsigned repository the ISO and install tests use.
To update a package, review the new AUR PKGBUILD diff, copy it here and
update this table.
