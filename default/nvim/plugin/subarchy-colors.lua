-- Subarchy: Subcult Ink is the default colour scheme. Plugins load after
-- your init.lua, so a scheme you chose there is kept.
if vim.g.colors_name == nil then
  pcall(vim.cmd.colorscheme, "subcult-ink")
end
