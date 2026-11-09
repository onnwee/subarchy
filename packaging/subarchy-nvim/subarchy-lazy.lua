-- Subarchy's copy of the LazyVim starter's lua/config/lazy.lua (Apache-2.0,
-- see NOTICE). Changed: lazy.nvim is not cloned at first start, it is in
-- the cache the package installs; the update checker is off, updates come
-- with the package (ADR 0045).
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.api.nvim_echo({
    { "lazy.nvim is missing from " .. lazypath .. "\n", "ErrorMsg" },
    { "Subarchy ships it in the subarchy-nvim package; reinstall it, or copy /etc/skel/.local/share/nvim to ~/.local/share.\n", "WarningMsg" },
  }, true, {})
  return
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = false, -- Subarchy: updates come with the package
    notify = false,
  },
  performance = {
    rtp = {
      -- lazy.nvim resets the runtime path to the config and its plugins;
      -- Subarchy's colour schemes live in the system site directory.
      paths = { "/usr/share/nvim/site" },
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
