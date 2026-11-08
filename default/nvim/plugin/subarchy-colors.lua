-- Subarchy: the theme-following Subcult scheme is the default colour
-- scheme (ADR 0045). Plugins load after your init.lua, so a scheme you chose
-- there is kept. LazyVim users get it through the subarchy plugin layer.
if vim.g.colors_name == nil then
  pcall(vim.cmd.colorscheme, "subcult")
end
