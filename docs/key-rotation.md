---
title: "Key rotation and revocation"
type: guide
status: draft
created: 2026-11-20
updated: 2026-11-20
tags: [guide, packages, security]
aliases: [Rotation procedure, Key revocation]
---

# Key rotation and revocation

How to replace or revoke the two keys Subarchy depends on, how an installed
system gets a new keyring, and what stops working at each step. Written
2026-11-20 for issue #263.

**Nothing in this procedure has been run.** It was written from the
repository at main `9e32591` and from Gitea's public documentation. No key
was rotated, no registry setting was changed and no installed system was
touched. Each step below is marked *untested*; the things that were
checked are listed under [[#What was checked]]. Rehearse the registry part
with [[#A rehearsal that touches nothing real]] before relying on it.

This note holds fingerprints and steps only. Never put key material, a
passphrase, a token or the path of a private key in the repository, an
issue or a pull request.

## The keys

| Key | What it signs | Where the private half is | Who trusts it |
|---|---|---|---|
| Registry key `CCE8 B0F3 BCDD 601D 9097 73E4 466A A6E8 2414 53D2` | The `stable` and `edge` package databases and every package the registry serves | Inside the Gitea instance behind `git.subcult.tv`. Nobody holds a separate copy that this repository records. | Every installed system and every CI job, through `subarchy-keyring` |
| The owner's release-image key | Meant for release images and their checksums ([[0025-package-repository\|ADR 0025]]) | On `soyuz` (ADR 0025, stated 2026-11-07). A second copy is not confirmed (#263). | Nobody yet: see below |

`SUBARCHY_PACKAGE_TOKEN` is a credential, not a key. Its rotation is in
[[package-publishing#Credential custody and rotation|Package publishing]]
and its reminder is under [[#Package token reminder]].

### Observed in the repository, 2026-11-20

- `packaging/subarchy-keyring/registry.key` holds one public key. `gpg
  --show-keys` on Kvant reads it as RSA 2048, created 2026-11-07, user ID
  "Arch Registry", with the fingerprint above, one encryption subkey and
  **no expiry date**. It will not expire by itself.
- `subarchy-trusted` lists that fingerprint with trust level 4.
  `subarchy-revoked` is empty.
- `subarchy-keyring` (`pkgver=20261108`) installs those three files under
  `/usr/share/pacman/keyrings/`. Its install script runs `pacman-key
  --populate subarchy` on install and on every upgrade.
- The package is in `install/packages/base.txt`, so every install has it.
  No other package depends on it.
- The installer installs from the image's own unsigned repository
  (`SigLevel = Optional TrustAll` in `install/subarchy-install`), runs
  `pacman-key --populate subarchy` in the target, then `subcult-channel set
  stable`, which registers `[subarchy]` with `SigLevel = Required`
  (`internal/channel/channel.go`). From the first boot on, the database and
  every Subarchy package must carry a signature from a trusted key.
- `subcult update` runs `pacman -Syu` (`internal/update/update.go`). That
  is the only way a new keyring reaches an installed system.
- CI takes the key from the checkout, not from an installed package:
  `tools/ci/build-iso.sh` copies the three keyring files into the build
  container, and the publish job in `.gitea/workflows/packages.yml`
  installs the keyring it just built. Both then require signatures.
- **No workflow or script signs a release image.** A search for `gpg`,
  `.sig` and checksum signing in `tools/` and `.gitea/workflows/` finds
  only the registry checks above. The owner's key's fingerprint is not
  recorded anywhere in this repository. Where the release image is hosted
  and how it is signed is undecided (#259).

### Stated elsewhere, not checked here

- ADR 0025 says the registry key is "generated per instance" (2026-11-08,
  answering Gitea #44). Where Gitea 28.3.0 stores the private half, and
  whether a database backup of the instance includes it, was not checked.
- [Gitea's Arch registry page](https://docs.gitea.com/usage/packages/arch/)
  (read 2026-11-20) describes downloading `repository.key` and trusting it.
  It documents no way to rotate, replace, export or import the key.
- Whether the registry stores a package's signature when the file is
  uploaded, or signs it again each time it is served, is not documented
  there and was not checked. Step B1.5 depends on the answer.

## Three limits to know first

1. **The registry signs whatever is uploaded.** Anyone holding
   `SUBARCHY_PACKAGE_TOKEN` can upload a package that installed systems
   will accept. A leaked token is therefore as serious as a leaked registry
   key for new package versions, and rotating the key does not fix it.
   Rotate the token ([[package-publishing#Credential custody and rotation|steps]])
   and audit the registry (step B2.2).
2. **The keyring travels through the repository it protects.** pacman
   checks every package of a transaction against the keys it trusted
   *before* the transaction. A keyring package signed only by a new key
   cannot be installed by a system that trusts only the old one. A planned
   rotation needs a period in which the old key signs a keyring that
   carries the new key (procedure B1). Without that period every installed
   system needs a manual step (procedure B3).
3. **Removing a key from `subarchy-trusted` does not remove trust.**
   `pacman-key --populate` imports the keys in the keyring file and
   locally signs those listed in `-trusted`; it never removes a key or a
   signature. A key leaves a system's trust only when its fingerprint is in
   `subarchy-revoked`, which makes `--populate` disable it, or when someone
   deletes it by hand. (Read in upstream `pacman-key.sh.in`, see
   [[#What was checked]]; not run.)

## A. The owner's release-image key

Installed systems never see this key. pacman does not use it, and no
package or update depends on it. Rotating or revoking it breaks nothing on
an installed system. It affects only people who verify a downloaded image.

Only the owner runs these steps. Agents must not read, move or copy the
key.

### A0. Before the first signed release (all untested)

These are not done, or not recorded, as of 2026-11-20:

1. Keep a second copy of the private key offline, and confirm it on #263
   by location class only (for example "encrypted USB stick in a safe").
2. Generate a revocation certificate for the key and keep it with the
   offline copy, not on `soyuz` alone. Without it, a lost key can never be
   revoked. A stored certificate carries the reason it was made with and
   that cannot be changed later without the private key, so the notice
   published with it must give the real reason and date.
3. Record the key's fingerprint in this note and publish the public key in
   the repository, once #259 decides how images are signed. Until then a
   downloader has nothing to check a signature against.
4. Decide the signature format in #259. The steps below assume a detached
   OpenPGP signature over a checksum file; adjust them if #259 chooses
   something else.

### A1. Planned rotation (untested)

| Step | What to do | What breaks |
|---|---|---|
| 1 | Generate the new key offline. Make its revocation certificate and second copy at once (A0.1, A0.2). | Nothing. |
| 2 | Sign the new public key with the old key, and write a short transition statement signed by both. | Nothing. |
| 3 | Open a pull request that adds the new public key and fingerprint beside the old one, with the date and the statement. | Nothing. Both keys are published. |
| 4 | Sign the current release's checksum file with the new key as well. Keep the old signature. | Nothing. Either key verifies the current release. |
| 5 | Sign new releases with the new key only. | Someone who trusts only the old fingerprint cannot verify new releases until they import the new key. The old key's signature on the new key (step 2) lets them check it. |
| 6 | After the overlap (suggested: one release, or 90 days), revoke the old key with the reason "superseded" and publish the revocation beside the public keys. | Signatures on old releases still verify but show a revoked key. Say so in the release notes. |

### A2. The key is compromised (untested)

1. Revoke the key at once and publish the revocation in the repository
   and wherever the public key was published. While the private key is
   still held, make a fresh revocation with the reason "compromised"
   (`gpg --gen-revoke`); otherwise publish the stored certificate from
   A0.2 and state the reason in the notice. Either way, give the earliest
   date the key may have been exposed. *Breaks:* every signature
   by the old key now shows as made by a revoked key, including good ones.
2. State on the release page which releases were signed before that date.
   Treat any image signed after it as unverified.
3. Generate a new key (A1 step 1). The old key cannot vouch for it. Its
   trust comes from the pull request that adds it to this repository,
   which GitHub and the Gitea mirror both carry.
4. Sign again, with the new key, the checksum files of releases that are
   still offered. Take the checksums from a source the old key did not
   protect: the CI run that built the image, or the second copy from #267.
   Do not copy them from a signed file whose signer is now revoked.
5. Rotate anything else that was on the same machine as the key.

### A3. The key is lost, not compromised (untested)

- With a second copy (#263): restore it. Nothing changes for anyone.
- Without one, with a revocation certificate: publish the certificate and
  say in the notice that the key was lost, not compromised (the
  certificate's own reason is fixed, see A0.2), then follow A2 steps 3
  and 4.
- With neither: the old key can never be revoked. Publish a new key and say
  in the repository that the old fingerprint is abandoned. Anyone who still
  trusts the old key gets no warning. This is why A0.1 and A0.2 come first.

## B. The registry key (the pacman trust root)

### B0. Preparation that makes the rest possible (all untested)

1. Find out where Gitea 28.3.0 keeps the registry's private key and whether
   the instance's backup contains it. If it does, restoring the instance
   after a loss keeps the same key and no client changes anything. If it
   does not, losing the instance forces procedure B2 on every system.
2. Find out how a new key can be created or imported, and whether the new
   public key can be known *before* the registry starts signing with it.
   Planned rotation (B1) is only possible if it can. If Gitea can only
   replace the key in place, every rotation is B2.
3. Find out whether stored packages are signed again after a key change
   (see "Stated elsewhere" above).
4. Record the answers here, with the Gitea version and the date.

### B1. Planned rotation with an overlap (untested)

Use this when the old key is not compromised and B0.2 showed the new public
key can be had in advance. "O" is the old key, "N" the new one.

| Step | What to do | What breaks |
|---|---|---|
| 1 | Obtain N's public key. Check its fingerprint by a second route, not only the download. | Nothing. |
| 2 | Keyring release 1: put both public keys in `registry.key`, list both fingerprints in `subarchy-trusted`, bump `pkgver` to the date. Merge. The registry, still signing with O, publishes it. | Nothing. The publish job's client check must pass. |
| 3 | Wait. Installed systems get release 1 through `subcult update`. There is no way to count how many have. Announce the date of step 4 in the release notes and on the site, and wait (suggested: 30 days). Each `main` build publishes the keyring to both `stable` and `edge`, so the wait is for users to run an update, not for a stable snapshot advance. | Nothing yet. |
| 4 | Switch the registry to sign with N. | **Every system that has not installed release 1 can no longer update.** `pacman -Sy` rejects the database signature. Those systems need B3. Old ISOs install offline as before, but the system they install is in this state from its first update. |
| 5 | Check what signs the packages already in the registry. If they still carry O's signature, each one must be published again under a new `pkgrel` before O can be revoked: published versions are immutable and the uploader skips a version that exists ([[package-publishing#Versions and retries\|why]]). The three files over 100 MB need the manual upload each time. | Nothing while both keys are trusted. If this step is skipped, step 6 makes the O-signed packages uninstallable. |
| 6 | Keyring release 2: remove O from `registry.key` and `subarchy-trusted`, add O's fingerprint to `subarchy-revoked`, bump `pkgver`. Update the fingerprint in this note, in [[package-publishing]] and in a progress note on ADR 0025. | A system still on release 1 keeps working: it trusts N. A system that never got release 1 stays broken until B3. |
| 7 | Build and publish a new ISO, so new installs start with release 2. Mark older images as needing B3 after install. | Nothing new. |

CI needs no separate change: the ISO build and the publish check read the
keyring files from the checkout, so they follow each keyring release on the
commit that makes it. Between step 4 and a merged keyring that trusts N,
both would fail, which is why step 2 comes first.

### B2. The registry key is compromised, lost or replaced without warning (untested)

This also applies if Gitea is reinstalled and generates a new key.

1. **Stop publishing.** Hold every pull request (`hold` label) so nothing
   merges to `main`, and say on the roadmap issue why. *Breaks:* no
   updates reach anyone.
2. **Find out what was served.** A stolen key is only useful to someone who
   can also deliver packages: through the registry (a package token or a
   Gitea account), through the host, or by intercepting HTTPS to
   `git.subcult.tv`. List the registry's packages and versions and compare
   them with the `main` runs of `.gitea/workflows/packages.yml` and with
   the manual uploads of files over 100 MB, which no run log shows
   ([[package-publishing#Two registry limits|why]]; today
   `nvidia-580xx-utils`, `proton-pass-bin` and `claude-code`). Anything
   neither accounts for is suspect; check a manual upload against the
   package its pinned PKGBUILD builds. Rotate `SUBARCHY_PACKAGE_TOKEN` in the same
   session.
3. **Replace the key** on the instance (mechanism from B0.2). *Breaks:*
   from this moment **no installed system can update**, because none of
   them trusts N. The ISO build and the publish check also fail until
   step 4 merges.
4. **Keyring release:** `registry.key` holds only N, `subarchy-trusted`
   lists only N, `subarchy-revoked` lists O, `pkgver` is bumped. This pull
   request is the public statement of the new fingerprint; it must be
   reviewed by the owner and merged from GitHub, which the registry's
   holder does not control. If a release key exists (A0), sign a statement
   of the new fingerprint with it as well.
5. **Publish again.** Remove the hold for that one pull request. The
   publish job's fresh-container check must pass against both channels
   with N. That check downloads every declared package with `SigLevel =
   Required`, so if stored packages still carry O's signature (B0.3,
   unknown) it fails on them: they are uninstallable everywhere and must
   be published again under a new `pkgrel` (step B1.5) before the job
   can pass.
6. **Tell users** how to recover (B3), in the release notes, on the site
   and in the repository README. Give the new fingerprint in full and the
   earliest date O may have been misused. Advise reinstalling every
   `[subarchy]` package installed or upgraded since that date, after B3.
7. **Build and publish a new ISO.** Withdraw older images or label them: a
   system installed from one trusts only O and needs B3 before its first
   update.
8. Record the incident and the new fingerprint as a dated progress note on
   ADR 0025, and update this note and [[package-publishing]].

### B3. What a user runs to trust a new registry key by hand (untested)

For a system that cannot update because it does not trust the current key.
The commands change what the system trusts, so the fingerprint check in
step 2 is the whole protection.

```bash
# 1. Fetch the public key from the repository, not from the registry.
curl -fLO https://raw.githubusercontent.com/subculture-collective/subarchy/main/packaging/subarchy-keyring/registry.key

# 2. Print its fingerprint. Compare all 40 characters with the fingerprint
#    in the release notes or the announcement on the site. Stop if they
#    differ. docs/package-publishing.md comes from the same repository as
#    the key file, so matching it alone proves nothing.
gpg --show-keys --with-fingerprint registry.key

# 3. Add and locally sign the new key.
sudo pacman-key --add registry.key
sudo pacman-key --lsign-key <new fingerprint>

# 4. Install the current keyring, then update. If that keyring lists the
#    old key as revoked, installing it disables the old key.
sudo pacman -Sy subarchy-keyring
subcult update
```

If step 4's first command still fails, the old key signed a package that
has not been published again (B1.5); report it instead of lowering
`SigLevel`. Do not set `SigLevel = Never` or `TrustAll` on `[subarchy]` to
get past an error: that removes the check this procedure restores.

No `subcult` command does this today. Whether to add one is a decision for
after B0, not part of this note.

### What a failure looks like

Not observed; pacman's wording was not captured. Expect `subcult update` to
stop in its package step with pacman reporting the `subarchy` database as
invalid or its signature as of unknown trust, before anything is installed.
`subcult update` takes its snapshot first, so a failed attempt leaves an
extra snapshot and no package change.

## Package token reminder

`SUBARCHY_PACKAGE_TOKEN` was created 2026-11-08 and is due for rotation by
**2027-02-06** ([[package-publishing#Credential custody and rotation|steps]]).
`.github/workflows/rotation-reminder.yml` runs every Monday. From
2027-01-06 it opens one issue titled "Rotate SUBARCHY_PACKAGE_TOKEN by
2027-02-06", and does nothing if an issue with that title already exists,
open or closed.

After each rotation, set `DUE` and `REMIND_FROM` in that workflow to the
next dates in the same pull request that updates the dates in
[[package-publishing]]. The new title makes a new issue.

Limits, as of 2026-11-20:

- The scheduled run is **untested**: GitHub runs schedules only from the
  default branch, so it cannot run before this is merged. The script inside
  it was run locally against a stand-in `gh` for five cases: before the
  window (from a manual run and from a schedule), inside it, with an
  existing issue, and forced.
- Whether the workflow's token may create issues in this organization is
  untested. After the merge, check it once with `gh workflow run
  rotation-reminder.yml -f open_now=true`; that opens the real issue early,
  which is harmless.
- The check for an existing issue uses GitHub's issue search, which the
  stand-in `gh` did not exercise. It is **untested** against the real
  search. After the first real run, run the same command a second time
  and confirm it reports the existing issue instead of opening another.
  If the search misses it, the workflow opens a duplicate every Monday.
- GitHub turns scheduled workflows off after 60 days without repository
  activity. This repository has had daily activity since 2026-11-06.
- The reminder covers this one token. The registry key has no expiry and
  the owner's key has no recorded one, so neither has a date to remind of.

## What was checked

| Check | Date, host | Result |
|---|---|---|
| `gpg --show-keys` on `packaging/subarchy-keyring/registry.key` | 2026-11-20, Kvant | Fingerprint, algorithm and creation date match ADR 0025; no expiry |
| Reminder script against a stand-in `gh`; `shellcheck` and `actionlint` 1.7.12 on the workflow | 2026-11-20, Kvant | Opens one issue inside the window or when forced; none before it or when one exists; no lint findings |
| `python3 tools/obsidian/check-vault.py` | 2026-11-20, Kvant | Passes |
| Review: each "Observed in the repository" item read against the named file at `9e32591`; the B3 step 1 URL fetched without credentials | 2026-11-20, Kvant | Items match the files; the URL returns HTTP 200 (the repository is public) |
| Second review: `populate_keyring` in upstream pacman's `scripts/pacman-key.sh.in` (master, fetched from gitlab.archlinux.org) read for limit 3 and for B1 step 6 and B2 step 4 | 2026-11-20, Kvant | It imports the keyring file, locally signs the `-trusted` keys and disables the `-revoked` ones; nothing removes a key. Disabling a key the system never had prints nothing and does not fail, so a fresh install of a keyring that lists only N as a key and O as revoked is not stopped by it. Read, not run, and not checked against the pacman version Subarchy ships |

Everything else in this note is untested.

## A rehearsal that touches nothing real

Not run. In a disposable Arch container with no network access to the
registry and no real key:

1. Make two throwaway signing keys, O and N, in a temporary GnuPG home.
2. Build a small package and a repository with `repo-add --sign` using O,
   and serve the directory over `file://` with `SigLevel = Required`.
3. Build a keyring package shaped like `subarchy-keyring` for O, install
   it, and confirm `pacman -Sy` and an install succeed.
4. Walk B1 steps 2, 4 and 6 and then B2 steps 3 and 4 against it, signing
   with `repo-add` where the real procedure says "the registry". Record
   pacman's exact messages under [[#What a failure looks like]] and whether
   B3 recovers the client.

This rehearses pacman and the keyring package. It says nothing about how
Gitea replaces or stores its key; only B0 answers that.

## Open items

- The owner's confirmation of the second key copy (#263).
- B0: how Gitea stores, backs up and replaces the registry key.
- The owner's key has no recorded fingerprint and signs nothing yet (#259).
- Installed systems have one trust root and no second path to a new one.
  ADR 0025 already names the alternative: a static repository built with
  `repo-add` and signed with a key the owner holds.

Related: [[package-publishing|Package publishing]] · [[0025-package-repository|ADR 0025]] · [[0026-update-model|ADR 0026]] · [[test-checklist|Test checklist]]
