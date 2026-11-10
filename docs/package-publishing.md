---
title: "Package publishing"
type: guide
status: active
created: 2026-11-08
updated: 2026-11-09
tags: [guide, ci, packages]
---

# Package publishing

`.gitea/workflows/packages.yml` builds the core, keyring and pinned packages
under `packaging/` in a disposable Arch container on `subarchy-kvm`. Builds
run as an unprivileged user. The build container and each PKGBUILD's build
dependencies follow the staged Arch snapshot in `default/pacman/snapshot`;
source checksums remain enforced. The build has no publishing
credential. Artifacts expire after three days.

PRs build packages and stop there. Only a push to `main` enables the
separate publishing job, which uploads artifacts from that same run to
both `stable` and `edge`:

```text
https://git.subcult.tv/api/packages/subculture-collective/arch/{channel}
```

The uploader also refuses any event/ref other than a push to
`refs/heads/main`. It sends credentials in an HTTP header. Availability
checks use a unique query string so a cached pre-upload 404 cannot hide the
new file from pacman.

## Versions and retries

The core keeps its semantic `pkgver` (starting at `0.0.0`, ADR 0066). CI
sets its `pkgrel` to the full checkout's Git commit count, so each main
commit has an ordered package version. Local builds keep the checked-in
release number. The build uses a full history checkout.

Other PKGBUILDs retain their reviewed versions. Bump `pkgver` or `pkgrel`
when changing their content. Published versions are immutable: the uploader
leaves an existing version alone, and the builder can reuse a pinned version
already present in both channels. It always rebuilds the core and keyring.
Both read "present" from the channel's signed database, the list pacman
resolves against. A request for a package file by name does not prove it:
the registry answered one for `nvidia-580xx-utils-…` with
`lib32-nvidia-580xx-utils-…`, so the 64-bit package and
`opencl-nvidia-580xx` were skipped as published and never uploaded, and
every publication on `main` failed its verification (found 2026-11-09).
An upload error fails the job; rerunning after a partial upload skips the
files that reached the registry. No existing package is deleted or replaced.

## Signing and client verification

The registry signs each uploaded package and its database using the
registry key from [[0025-package-repository|ADR 0025]]:

```text
CCE8B0F3BCDD601D909773E4466AA6E8241453D2
```

The owner's release-image key is separate and never enters this workflow.
See [Gitea's Arch registry documentation](https://docs.gitea.com/usage/packages/arch/)
for its upload and client interface.

After publishing, a fresh job container installs the built keyring,
populates pacman's trust store, and synchronizes both channel databases
with `SigLevel = Required`. It downloads every declared package through
pacman, then installs `subarchy` with its dependencies. Database and package
signature failures fail this job.

On installed systems, `subcult channel set stable` or `edge` registers
`[subarchy]` with `SigLevel = Required` if the section is missing. Its server
comes from `/etc/pacman.d/subcult-repo`. Existing custom Subarchy sections
are left intact; those must include that file and require signatures.

The ISO's local unsigned bootstrap repository is separate. CI registry
verification does not qualify a physical installation or an offline ISO.

## Credential custody and rotation

Gitea 28.3.0's package access check does not grant writes to Actions job
identities. The native repository secret `SUBARCHY_PACKAGE_TOKEN` therefore
holds a dedicated token for `subcult-agent`, named
`subarchy-packages-20261108`, scoped only to `write:package`. This Gitea
scope covers package registries accessible to that identity; it cannot be
restricted to one package name. It grants no repository or admin API scope.
Only the main publishing step receives it.

Created 2026-11-08; rotate by 2027-02-06. Create a new package-only token,
feed it to `tea actions secrets create --login subcult-agent --stdin
SUBARCHY_PACKAGE_TOKEN` through private standard input, and run a main
publication. Check its signed client verification before revoking the old
token by name in the agent account's application settings. Preserve other
device/service credentials. If the replacement fails, correct it or issue
another package-only replacement and verify publication before cleanup.
Never put either token in a URL, command argument, issue or Git file.

Related: [[0025-package-repository|Package repository and signing]] · [[ci-runner|KVM CI runner]] · [[0066-versioning|Versioning]]
