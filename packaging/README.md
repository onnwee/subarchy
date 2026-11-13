# packaging

PKGBUILDs and the pacman repository definition. Omarchy publishes 256 packages at `https://pkgs.omarchy.org/stable/$arch` ([list](../docs/inventory/generated/omarchy-repo-packages.md)). The SUBCULT rice already has release and VCS PKGBUILD designs in `subcult-omarchy-rice/packaging/arch/`.

| Directory | What |
|---|---|
| `subarchy/` | The distribution's own package: `subcult`, the defaults, the shell and the OS identity |
| `aur/` | Reviewed, pinned AUR PKGBUILDs rebuilt into Subarchy's repository (ADR 0025); `aur/build.sh` builds them, and the packages below, in a clean container |
| `subarchy-nvim/` | Neovim with LazyVim prebuilt (ADR 0045): the starter at a pinned commit, `lazy-lock.json`, and the cached plugins for `/etc/skel`; its build fetches the plugins |
| `subarchy-keyring/` | The package that installs the repository signing key and trusts it in pacman-key (ADR 0025) |
| `pult/` | Pult, the theme tool, vendored from its release PKGBUILD (ADR 0037) |
| `linecast/` | [linecast](https://github.com/ashuttl/linecast) from a pinned tag (MIT), which the weather widget calls for forecast, sun, moon and tides |
