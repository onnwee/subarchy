# subarchy-nvim

Neovim with stock LazyVim, prebuilt (ADR 0045): the LazyVim starter at a
pinned commit, one changed file (`subarchy-lazy.lua`, see `NOTICE`), and
every plugin at the commit `lazy-lock.json` names, cached in the package.
The installer's new user gets both from `/etc/skel`, so the first `nvim`
needs no network.

`build()` fetches the plugins with `nvim --headless "+Lazy! restore"`, so the
build needs the network; `packaging/aur/build.sh subarchy-nvim` runs it in
the clean container like the other packages.

To update the plugins: in a scratch home, copy the starter config with
`subarchy-lazy.lua` in place, run `nvim --headless "+Lazy! sync" +qa`, review
the new `lazy-lock.json` against the old one, copy it here and rebuild. To
move the starter: bump `_starter` and its sha256.
