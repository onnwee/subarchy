---
title: "Go application notice retention"
type: review
status: draft
review: done
created: 2026-11-16
updated: 2026-11-20
tags: [review, packaging, licence]
---

# Go application notice retention

Refs [#243](https://github.com/subculture-collective/subarchy/issues/243),
roadmap [#230](https://github.com/subculture-collective/subarchy/issues/230),
and the packaged-licence criterion in
[#84](https://github.com/subculture-collective/subarchy/issues/84).
This note records a focused retention repair, not release-wide legal clearance.
Default: retain the proven texts now; keep #243 open until final-source package
builds, review and both-channel publication/readback are complete. Keep the
remaining source-delivery, applicability and final-image questions under #84.

## Source and package scope

The 2026-11-16 read-only audit on Kvant inspected signed Pult
`0.4.1.r2.g7a703f1-1`, yay `13.1.0-1` and cliamp `2.4.1-1`. The three application
archives matched their recipe SHA-256 values. All 136 recorded module occurrences
matched source `go.sum`; the 122 unique module archives matched embedded h1 sums.
The parent independently rehashed the 91 proposed retained texts: 27 Pult, 9 yay,
55 cliamp. These are source-text inventory counts, not separate legal defects or
a required file count. This implementation used that evidence without repeating
the full audit. The application source pins and existing checksums are unchanged
from main `19f4b54b2ab7e773b04718772fc3610c9ab76b44` (PR #242).

Each package folder contains a static `THIRD-PARTY-NOTICES.txt` and
`THIRD-PARTY-NOTICES.provenance.json`. The JSON records module/version, primary
source URL, module h1, exact text SHA-256, byte length and byte offset in the
bundle. Linked-source attribution excerpts also map each verbatim line to its
source files. The bundle gives readable module/version/path headings. Exact
duplicates and exact contained bytes share a section; formatting variants remain
distinct to preserve their original byte hashes. Source text, including author
names, years, NOTICE contents and additional headers, is copied without rewriting.

Common Go, GNU and Apache terms accompany each standalone package. An optional
Neovim or LocalSend package is not needed to read them. Pult's Pelletier TOML
2.4.3 text is separate from core's BurntSushi TOML 1.5.0 notice. The bundles retain
YAML/Canonical, modernc/mmap/musl, gotext's MIT/BSD and modification attributions,
and cliamp's linked Goja Lucent/V8, protobuf, gRPC and other proven notices.
Metadata-only, example, test and unlinked nested notices are excluded from this
repair; MongoDB's broad aggregation is not copied as proven runtime material.

The changed package releases are Pult `0.4.1.r2.g7a703f1-2`, yay `13.1.0-2` and
cliamp `2.4.1-2`. Their `package()` functions install the bundle and provenance as
independent regular files with mode 0644 under `/usr/share/licenses/<package>/`.
Existing Pult GPL, MIT and HuJSON files and cliamp's own MIT file remain separate;
yay also installs its own upstream `LICENSE` explicitly. Recipe licence metadata
names the added terms. cliamp's LicenseRefs identify the exact retained Lucent
and go-librespot GPL texts without deciding the outstanding source-delivery or
compatibility questions. No application or dependency version is changed.

## xlab clarification

The pinned xlab/vorbis-go archive at `b5b85f1ec645f3cffd000583b7c7f60b45d95379`
contains no named licence file. On 2026-10-30, upstream maintainer `xlab` added an
MIT [LICENSE in commit 7a1a428](https://github.com/xlab/vorbis-go/commit/7a1a42804d4d9f8eb7466be0b953c18069c6c271),
attributed to **2015–2021 Maxim Kupriianov**. The
[primary comparison](https://github.com/xlab/vorbis-go/compare/b5b85f1ec645f3cffd000583b7c7f60b45d95379...cfbc67241c69b72f281ab3e1303ca90719e66d00)
is two commits ahead and changes only `LICENSE`, `go.mod` and `go.sum`; wrapper
and runtime source is identical. This implementation independently checked the
GitHub comparison, licence commit and exact licence bytes. SHA-256:
`fc535686ab935d5776543a21c729f3081d53cd50b81ea07f6b1321c20e935ba3`.

cliamp carries that actual MIT text with explicit later-commit provenance and
the unchanged-source comparison in its mapping. This resolves the missing
upstream text for identical wrapper source. It does not establish universal
legal clearance or settle third-party header and source-delivery questions.

## Verification and remaining gates

`python3 tools/test/go-app-notices-test.py` runs the real three `package()`
functions against small upstream-output fixtures with only each package folder
available. It checks package-local input hashes, attributed byte ranges, original
source-hash anchors, readable regular files, existing application licence copies
and archive round trips. Negative cases remove files, change bytes, restrict
readability and substitute symlinks. The yay fixture replaces upstream's make
install target to avoid building code or translating locales; it exercises the
recipe's actual notice installs. These are packaging checks, not real app builds.
The check runs through `make docs-check` and therefore hosted `make verify`.

The portable Pult checker copies the local inputs, resolves local and remote
`source` entries separately, and verifies the staged notices after its normal
build/check. The main builder and `packaging/aur/build.sh` use makepkg's normal
local-source handling; no private cache path is a packaging or test dependency.

For real final-source archives, the parent can run:

```bash
python3 tools/test/go-app-notices-test.py --archive pult build/packages/pult-0.4.1.r2.g7a703f1-2-x86_64.pkg.tar.zst
python3 tools/test/go-app-notices-test.py --archive yay build/packages/yay-13.1.0-2-x86_64.pkg.tar.zst
python3 tools/test/go-app-notices-test.py --archive cliamp build/packages/cliamp-2.4.1-2-x86_64.pkg.tar.zst
```

The archive mode needs `bsdtar`. It checks the exact original application licence
hashes as well as the installed bundle/provenance. `--staged` accepts an extracted
package root for the same check. Neither mode installs or executes applications.

Outstanding evidence and decisions:

- Independent review and hosted CI on the final PR head, then real changed-app
  builds and inspection from that reviewed source. Local application builds,
  containers and VMs were deliberately excluded from this implementation lane.
- Signed publication and database/archive readback in **both** channels before
  merging the new recipe releases, so the exact-version ISO path stays usable.
- Per-section applicability of MongoDB's `THIRD-PARTY-NOTICES`: the audit
  recovered BSON code, while the aggregation includes unlinked/test components.
- GPL/MPL corresponding-source delivery, notices of source availability and
  compatibility review, including yay's GPL modules/go-multierror MPL and
  cliamp's go-librespot GPL text. Shipping licence text alone does not settle
  these requirements. Broader modernc subcomponent applicability remains limited
  to the proven runtime material in the audit.
- Actual final ISO/filesystem placement, readability and common-text mapping,
  including the new core notices from #242. Earlier CI logs and cached package
  evidence do not prove final image-byte coverage.
- The original #84 hardware, release-asset and owner release-decision gates.

No release, tag, visibility change, contract acceptance, owner profile access or
Sputnik operation is part of this change. Native application acceptance in #78
stays separate.

Related: [[review-index]] · [[0053-licence]] · [[0051-hosting-ci]] · [[pult-app-targets]]
