# Third-party notices

These notices were retained verbatim on 2026-11-15 and 2026-11-16.
The Subarchy package installs them beside its own GPL notice under `/usr/share/licenses/subarchy/`.

| Notice | Source | Used here |
|---|---|---|
| [Omarchy-MIT.txt](Omarchy-MIT.txt) | `basecamp/omarchy`, `LICENSE`, Git blob `f12cfa766c55541c9d8e008e310c95a721e70a97` | The three capture scripts, Hyprland bindings/helpers, Starship prompt and shell aliases carry origin headers pointing here |
| [SUBCULT-rice-MIT.txt](SUBCULT-rice-MIT.txt) | `subcult-omarchy-rice` at `05a7b506f888b0f9f09d5dc48a3cdba7ad6ad3ad`, `LICENSE` | Retained with that source's asset notice |
| [SUBCULT-rice-ASSETS.txt](SUBCULT-rice-ASSETS.txt) | The same rice revision, `ASSETS_LICENSE.md` | The original SUBCULT marks and seven wallpapers described in `branding/README.md` |

The branding directory records the separately supplied Studio artwork.
Fonts keep their own OFL texts; Departure Mono's text is also installed as
`DepartureMono-OFL.txt`. Third-party application packages carry their own
notices in their respective package licence directories.

## Linked Go code (2026-11-16)

Core634's packaged Go binaries were inspected with `go version -m`: their
three external modules are the versions below. The Go runtime and both
`golang.org/x` module licence files are byte-identical, so one unchanged
text covers all three. These texts are installed with the core package;
they do not relicense Subarchy or establish rights to unrelated assets.

| Notice | Pinned primary source | SHA-256 |
|---|---|---|
| [Go-BSD-3-Clause.txt](Go-BSD-3-Clause.txt) | [Go go1.27.4](https://raw.githubusercontent.com/golang/go/go1.27.4/LICENSE), [x/sys v0.49.0](https://raw.githubusercontent.com/golang/sys/v0.49.0/LICENSE), [x/term v0.47.0](https://raw.githubusercontent.com/golang/term/v0.47.0/LICENSE) | `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| [TOML-MIT.txt](TOML-MIT.txt) | [BurntSushi/toml v1.5.0, COPYING](https://raw.githubusercontent.com/BurntSushi/toml/v1.5.0/COPYING) | `d21cb1c60785d6d3a84a7059323ccafc45c645b1bbda281c76a62d66ad2d7dc3` |

Recheck the notice sources when the module or toolchain versions change.
