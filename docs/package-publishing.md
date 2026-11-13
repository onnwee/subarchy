---
title: "Package publishing"
type: guide
status: active
created: 2026-11-08
updated: 2026-11-13
tags: [guide, ci, packages]
---

# Package publishing

`.gitea/workflows/packages.yml` builds the core, keyring and pinned packages
under `packaging/` in a disposable Arch container on `subarchy-kvm`. Builds
run as an unprivileged user. The build container and each PKGBUILD's build
dependencies follow the staged Arch snapshot in `default/pacman/snapshot`;
source checksums remain enforced. The build has no publishing
credential. Artifacts expire after three days.

Pull requests are on GitHub, where `.github/workflows/mirror-ci.yml`
builds and checks only the core package. The keyring, pinned and AUR
rebuilds run here on Gitea `main` ([[0051-hosting-ci|ADR 0051]]). Only a
push to `main` enables the separate publishing job, which uploads artifacts from that same run to
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

## Two registry limits

**File names must not contain one another.** Gitea's Arch registry finds a
package file by substring. With only `lib32-nvidia-580xx-utils-580.196.07-1`
present it served that file for `nvidia-580xx-utils-580.196.07-1`; with both
present it answers 404 for the shorter name (observed 2026-11-09, after both
were uploaded). The builder refuses such a pair before it builds
(`publish-packages.py --check-names`). The fix is a different `pkgrel` on
one of them: `nvidia-580xx-utils` carries `-2` against the lib32 package's
`-1`. The unreachable `nvidia-580xx-utils` and `opencl-nvidia-580xx`
`580.196.07-1` versions stay in the registry; the databases list `-2`.

**The public route refuses uploads over 100 MB.** Cloudflare in front of
`git.subcult.tv` answers HTTP 413, and `nvidia-580xx-utils` is about
360 MB, and `proton-pass-bin` (145 MB); each new version of them needs
the upload below before its PKGBUILD changes. `claude-code` (154 MB)
waits outside `packaging/aur` until its file is uploaded this way. The uploader stops with a message naming the file, and it
uploads in name order, so until such a file is in the registry the files
after it, the core included, are not published either. Until CI has a
route for such files, build that PKGBUILD in a clean Arch container
(`packaging/aur/build.sh` does) and upload the file through an SSH forward
to Gitea's origin on Almaz, so the token does not cross the network in
clear text:

```bash
ip=$(ssh almaz "docker inspect gitea --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}'" | awk '{print $1}')
ssh -f -N -L 127.0.0.1:43833:"$ip":3000 almaz
# PUT the file to http://127.0.0.1:43833/api/packages/subculture-collective/arch/<channel>
# with "Authorization: token …" and "Host: git.subcult.tv", once per channel.
ssh -O cancel -L 127.0.0.1:43833:"$ip":3000 almaz
```

The next run on `main` then finds the version in the database, skips it and
uploads the rest. Downloads are not limited.

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

## Advancing the stable snapshot

The stable channel takes Arch packages from one day of the Arch Linux
Archive, the date in `default/pacman/snapshot` ([[0026-update-model|ADR 0026]]).
Every Monday around 06:00 UTC, the user timer `subarchy-snapshot.timer` on
Kvant runs `tools/ci/advance-snapshot.sh`. The script tries yesterday's
date: in a privileged Arch container with KVM, capped at four CPUs and 8 GB
inside `batch.slice`, it builds the ISO against that day and runs the
guided offline VM install test. This is the same pair of scripts the iso
workflow runs.

- If it passes, the script pushes `chore/snapshot-YYYY-MM-DD` to GitHub and
  opens a pull request. That pull request merges itself once the required
  checks pass. The next main build then publishes packages built against
  the new day.
- If it fails, the script opens an issue titled "Stable snapshot … failed
  the install test" with the end of the log, or comments on the open one,
  and stable stays where it was. The full log is
  `~/.cache/subarchy-snapshot/last-run.log` on Kvant.

The units live in `tools/ci/systemd/`. The service refreshes its own clone
of main before each run, so changes to the script take effect on the next
run. To install or remove them:

```bash
cp tools/ci/systemd/subarchy-snapshot.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now subarchy-snapshot.timer
# remove: systemctl --user disable --now subarchy-snapshot.timer, then delete both files
```

To try a given day without pushing anything, run
`SUBARCHY_SNAPSHOT_DATE=2026/11/11 SUBARCHY_SNAPSHOT_DRY=1 tools/ci/advance-snapshot.sh`.
The edge channel needs none of this: it follows Arch's mirrors directly.

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
