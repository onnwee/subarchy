# Package sources

These are development packages, not a released ISO. Use the version-specific
downloads and sources below together. The package hashes are from the
2026-11-16 publication receipts; source hashes are from the pinned-source
checks. An anonymous link check establishes access, not a new byte audit.

## Downloads and recipe revisions

| Package (x86_64) | Binary archive | Subarchy recipe and local notice inputs |
|---|---|---|
| Core `0.0.0-636` | [Download](https://git.subcult.tv/api/packages/subculture-collective/arch/stable/x86_64/subarchy-0.0.0-636-x86_64.pkg.tar.zst) | [Core recipe at actual build revision `8d06f86`](https://github.com/subculture-collective/subarchy/blob/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/packaging/subarchy/PKGBUILD); [complete checkout](https://github.com/subculture-collective/subarchy/archive/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a.tar.gz) |
| Pult `0.4.1.r2.g7a703f1-2` | [Download](https://git.subcult.tv/api/packages/subculture-collective/arch/stable/x86_64/pult-0.4.1.r2.g7a703f1-2-x86_64.pkg.tar.zst) | [Recipe directory at `8d06f86`](https://github.com/subculture-collective/subarchy/tree/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/packaging/pult) |
| yay `13.1.0-2` (historical notice bundle) | [Download](https://git.subcult.tv/api/packages/subculture-collective/arch/stable/x86_64/yay-13.1.0-2-x86_64.pkg.tar.zst) | [Recipe directory at `8d06f86`](https://github.com/subculture-collective/subarchy/tree/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/packaging/aur/yay) |
| yay `13.1.0-3` (BSON notice repair) | [Download](https://git.subcult.tv/api/packages/subculture-collective/arch/stable/x86_64/yay-13.1.0-3-x86_64.pkg.tar.zst) | [Recipe directory at `475322d`](https://github.com/subculture-collective/subarchy/tree/475322dd97626d510a25cebc432acd9045a615a6/packaging/aur/yay); [complete checkout with helpers](https://github.com/subculture-collective/subarchy/archive/475322dd97626d510a25cebc432acd9045a615a6.tar.gz) |
| cliamp `2.4.1-2` | [Download](https://git.subcult.tv/api/packages/subculture-collective/arch/stable/x86_64/cliamp-2.4.1-2-x86_64.pkg.tar.zst) | [Recipe directory at `8d06f86`](https://github.com/subculture-collective/subarchy/tree/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/packaging/aur/cliamp) |

The same published versions are also served from `arch/edge/x86_64` in place
of `arch/stable/x86_64`. Detached signatures are at each archive URL plus
`.sig`; use the [tracked repository keyring](https://github.com/subculture-collective/subarchy/tree/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/packaging/subarchy-keyring)
and the channel's signed `subarchy.db` to verify downloads.

| Archive | SHA-256 |
|---|---|
| `subarchy-0.0.0-636-x86_64.pkg.tar.zst` (29,737,587 bytes) | `f11af33f4c1cda74126e65071a401063c8d8e30019fbb9a3f6e4b85432c7425c` |
| `pult-0.4.1.r2.g7a703f1-2-x86_64.pkg.tar.zst` | `1d8e11db38f766e905774866a136d59069c89f95f74e39577d49879bc31b3bdc` |
| `yay-13.1.0-2-x86_64.pkg.tar.zst` | `680b53ef62f293e8a7bf4aec52578972f4cb001e116978b530991edf379d3c63` |
| `yay-13.1.0-3-x86_64.pkg.tar.zst` (4,981,659 bytes) | `d66f9266809f045b75d2fe2bc2687102ca50b6375d91e562b6f58878fa63f597` |
| `cliamp-2.4.1-2-x86_64.pkg.tar.zst` | `501151f3e46d6bbd2e35fac288b45022b64415be16935fb4adc36b43101188a8` |

### Core: select the actual build revision

Core is built from the complete Subarchy checkout, including `cmd/`,
`internal/`, `shell/`, `lock/`, defaults, assets, installation scripts and
the recipe's helper inputs. It has no upstream `source=()` archive.
The source for the core636 archive above is
`8d06f8618f41d9740ecf25536790b1aeb6ae9e6a`. This row does not bind any later
core or final ISO to that revision.

For another core version, read the archive's `.PKGINFO` (name/version) and
`.BUILDINFO` (recipe checksum, toolchain and installed build packages) with
`bsdtar -xOf`. On the matching installed package, `go version -m /usr/bin/subcult`
reports `vcs.revision` and `vcs.modified` when Go recorded them. Match that
revision to the CI checkout and publication receipt for the archive's hash.
If VCS metadata is absent or says modified, obtain the actual checkout
revision and any changes from that build's receipt before selecting source.
Use the full commit to retrieve a Git checkout or GitHub source archive.

The [CI driver](https://github.com/subculture-collective/subarchy/blob/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/tools/ci/build-packages.sh)
sets core's package release from `git rev-list --count HEAD`. Tracked
`pkgrel=1`, a commit count alone, and today's `main` do not identify a
package's source. For later publication, add a separate version/hash/revision
row from the actual receipt; keep this baseline scoped to core636.

## Application source and extra inputs

Download complete source trees, including `go.mod`, `go.sum`, Makefiles,
licences and source notices. The recipes above record Subarchy's build flags
and installed files. No application or dependency version changes in yay -3.

| Package | Full upstream source | Source archive SHA-256 |
|---|---|---|
| Pult | [Commit `7a703f18d2a934d5c4821c24a723c0ad4863417d`](https://api.github.com/repos/subculture-collective/pult/tarball/7a703f18d2a934d5c4821c24a723c0ad4863417d) | `bd764cd6a3d8c99729d6968a3c85ed9de59d0ed467639938968beee133bfd996` |
| yay -2 and -3 | [yay v13.1.0](https://github.com/Jguer/yay/archive/v13.1.0.tar.gz) | `acd3c97fac52449ba3589fefc076b90f42fa5072ef274f5bcbcd381f50b2701a` |
| cliamp | [cliamp v2.4.1](https://github.com/bjarneo/cliamp/archive/refs/tags/v2.4.1.tar.gz) | `fb5e43513b71287cd1db39403a293436b38db2ffa73fcd820a34ba3a73d2523e` |

Pult also embeds the [v0.4.1 catalogue](https://git.subcult.tv/subculture-collective/pult/releases/download/v0.4.1/pult-0.4.1-catalog.db.zst),
SHA-256 `c05372aa5f627d8875d6be499babe73abe30afa909b3557f9d520b356e1c4cc3`.
Its recipe copies that exact input into `builtin/catalog.db.zst`; retain
the catalogue's theme provenance as well as the code sources. The pinned
[Pult source tree](https://github.com/subculture-collective/pult/tree/7a703f18d2a934d5c4821c24a723c0ad4863417d)
includes its catalogue tooling, templates and registry inputs.

### Complete Go module sources

From each complete application tree, or the Subarchy root for core, use its
own `go.mod` and `go.sum` with the recorded Go version. In a separate source
workspace, resolve all modules and verify their contents:

```sh
GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org go mod download all
go mod verify
go list -m -json all
```

`go mod download -json all` reports each module's ZIP, extracted directory,
version and `Sum`; compare sums with `go.sum`. The public Go proxy supplies
full module ZIPs, `.mod` and `.info` files under
`https://proxy.golang.org/<escaped-module>/@v/<version>` (uppercase letters
escape as `!` plus lowercase). Follow any `replace` directives and retain
local replacements from the full source tree. Keep build/test inputs too;
the installed notice inventory alone is not the complete module graph.
Do not disable checksum verification.

Each app's `THIRD-PARTY-NOTICES.provenance.json`, in the recipe directory and
installed under `/usr/share/licenses/<package>/`, also gives exact module
ZIP URLs and h1 checksums beside the retained texts. For example:
[MongoDB v1.17.9](https://proxy.golang.org/go.mongodb.org/mongo-driver/@v/v1.17.9.zip),
`h1:IexDdCuuNJ3BHrELgBlyaH9p60JXAvdzWR128q+U5tU=`. Retain whole sources,
including the BSON source headers and `THIRD-PARTY-NOTICES` aggregation.

### Helpers and recorded build environment

Use the full Subarchy checkout at the recipe revision above, not just a
copied PKGBUILD. It includes local notice inputs, the
[container build helper](https://github.com/subculture-collective/subarchy/blob/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/packaging/aur/build.sh),
[Pult check helper](https://github.com/subculture-collective/subarchy/blob/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/tools/test/pult-app-targets-test.py),
[core asset helpers](https://github.com/subculture-collective/subarchy/tree/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/tools),
and the [package workflow](https://github.com/subculture-collective/subarchy/blob/8d06f8618f41d9740ecf25536790b1aeb6ae9e6a/.gitea/workflows/packages.yml).
Those helpers are unchanged in `475322d`; use that checkout for yay -3's
updated notices and recipe. Run the selected recipe with normal `makepkg`
in the recorded Arch environment when rebuilding.

Every binary archive carries `.BUILDINFO` and `.PKGINFO`; inspect them
without installing it. `.BUILDINFO` records the recipe SHA-256, build date,
architecture and installed package versions; binary Go metadata records
the toolchain/build settings. The workflow/helper explains setup and flags.
The helper uses `archlinux:latest`, so today's container is not proof of the
old environment. The stable installation snapshot is `2026/11/15`; it is
separate from the builder's recorded package set. Obtain required Arch
package sources through the official [version-specific packaging route](https://man.archlinux.org/man/pkgctl-repo-clone.1.en),
using `.BUILDINFO` versions and the Arch Linux Archive as needed for build
tools. An Arch binary mirror is not source code. Ordinary makepkg source
arrays do not capture Go's fetched modules or core's checkout by themselves.

## Distribution terms

Pult code is GPL-3.0-only; its templates/registry retain MIT and its copied
HuJSON code and dependencies retain their own notices. Yay's GPL3 combined
distribution retains its MIT, BSD, Apache and MPL notices, including the
copied BSON BSD text added in -3.

Yay's unchanged `github.com/hashicorp/go-multierror v1.1.1` files remain
available under MPL-2.0 from the [full module source](https://proxy.golang.org/github.com/hashicorp/go-multierror/@v/v1.1.1.zip),
`h1:H5DkEtf6CXdFp0N0Em5UCwQpXMWke8IA0+lD48awMYo=`. Preserve their MPL
notices and source option. The pinned source has no applied secondary-licence
prohibition; the standard Exhibit B template in the licence is not an
application of that prohibition. [Mozilla's guidelines](https://www.mozilla.org/en-US/MPL/2.0/combining-mpl-and-gpl/)
explain unchanged MPL files in a GPL larger work; no source-header rewrite
or dependency replacement is needed here.

Cliamp's combined executable is distributed under GPL3 because it links
the GPL3 `github.com/devgianlu/go-librespot v0.9.1` runtime. Original cliamp
files retain their MIT grant, and all other retained dependency notices
continue to apply. Obtain [go-librespot's complete source](https://proxy.golang.org/github.com/devgianlu/go-librespot/@v/v0.9.1.zip),
`h1:cgHB0Qo3GgqBe+8iZ1qw+kPJVp1s0obTlTXMdPsgb0U=`, through that route
and the complete module graph above. The upstream MIT label alone does not
describe the combined executable's terms.

These directions use the existing source servers beside the binary links
([GNU guidance](https://www.gnu.org/licenses/gpl-faq.html#SourceAndBinaryOnDifferentSites)).
They cover the named package versions. Yay -3 was built with normal makepkg
from the unchanged recipe and notice inputs at `475322d`, using Arch snapshot
`2026/11/15`. On 2026-11-16, both stable and edge signed database entries and
package signatures verified against the tracked registry key, and public
downloads matched the size and SHA-256 above. The archive retained the exact
BSON notice and copied-origin attribution with regular, root-owned 0644
licence files. [#247](https://github.com/subculture-collective/subarchy/issues/247)
records that bounded package/source qualification.
The later core build/source binding and final ISO notice placement remain
under [#241](https://github.com/subculture-collective/subarchy/issues/241)
and [#84](https://github.com/subculture-collective/subarchy/issues/84).
