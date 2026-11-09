-- Subcult: the colour scheme that follows the active theme (ADR 0045, ADR
-- 0037). It reads the palette Theme Tender applies for the user
-- (~/.config/subcult/theme/palette.json), else the system default palette,
-- and maps its roles to highlight groups. Without any palette it is
-- Subcult Ink.
local function read_palette()
  local paths = {
    (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") or "") .. "/.config") .. "/subcult/theme/palette.json",
    (os.getenv("SUBCULT_PATH") or "/usr/share/subcult") .. "/default/theme/palette.json",
  }
  for _, path in ipairs(paths) do
    local f = io.open(path, "r")
    if f then
      local text = f:read("*a")
      f:close()
      local ok, data = pcall(vim.json.decode, text)
      if ok and type(data) == "table" and type(data.colors) == "table" and data.colors.base and data.colors.text then
        return data.colors
      end
    end
  end
  return nil
end

local c = read_palette()
if not c then
  -- Sourced directly: a nested :colorscheme inside a scheme file does not
  -- take effect in Neovim.
  vim.cmd("runtime colors/subcult-ink.lua")
  vim.g.colors_name = "subcult"
  return
end

vim.cmd("highlight clear")
vim.o.termguicolors = true
vim.o.background = "dark"
vim.g.colors_name = "subcult"

local function role(name, fallback)
  return c[name] or c[fallback] or c.text
end

local hl = function(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

local base, mantle, crust = role("base"), role("mantle", "base"), role("crust", "mantle")
local surface0, surface1 = role("surface0", "mantle"), role("surface1", "surface0")
local overlay0 = role("overlay0", "surface1")
local text, subtext1, subtext0 = role("text"), role("subtext1", "text"), role("subtext0", "subtext1")
local selection = role("selection_bg", "surface1")
local mauve, lavender, blue, sky = role("mauve"), role("lavender", "mauve"), role("blue", "lavender"), role("sky", "blue")
local teal, green, peach, yellow, red = role("teal", "green"), role("green", "teal"), role("peach", "yellow"), role("yellow", "peach"), role("red")

hl("Normal", { fg = text, bg = base })
hl("NormalNC", { fg = subtext1, bg = base })
hl("NormalFloat", { fg = text, bg = mantle })
hl("FloatBorder", { fg = overlay0, bg = mantle })
hl("Comment", { fg = subtext0 })
hl("String", { fg = teal })
hl("Constant", { fg = peach })
hl("Number", { fg = peach })
hl("Boolean", { fg = peach })
hl("Identifier", { fg = text })
hl("Function", { fg = lavender })
hl("Statement", { fg = mauve })
hl("Keyword", { fg = mauve })
hl("Type", { fg = blue })
hl("PreProc", { fg = yellow })
hl("Special", { fg = lavender })
hl("Delimiter", { fg = subtext1 })
hl("Operator", { fg = subtext1 })
hl("LineNr", { fg = subtext0, bg = base })
hl("CursorLineNr", { fg = mauve, bg = surface0 })
hl("CursorLine", { bg = surface0 })
hl("CursorColumn", { bg = surface0 })
hl("ColorColumn", { bg = surface0 })
hl("Visual", { bg = selection })
hl("Search", { fg = text, bg = selection })
hl("IncSearch", { fg = crust, bg = yellow })
hl("CurSearch", { fg = crust, bg = yellow })
hl("StatusLine", { fg = text, bg = surface0 })
hl("StatusLineNC", { fg = subtext0, bg = mantle })
hl("WinSeparator", { fg = overlay0 })
hl("Pmenu", { fg = text, bg = mantle })
hl("PmenuSel", { fg = text, bg = selection })
hl("PmenuSbar", { bg = surface0 })
hl("PmenuThumb", { bg = overlay0 })
hl("TabLine", { fg = subtext0, bg = mantle })
hl("TabLineSel", { fg = text, bg = selection })
hl("TabLineFill", { bg = mantle })
hl("SignColumn", { fg = subtext0, bg = base })
hl("Folded", { fg = subtext0, bg = surface0 })
hl("FoldColumn", { fg = subtext0, bg = base })
hl("NonText", { fg = overlay0 })
hl("Whitespace", { fg = overlay0 })
hl("EndOfBuffer", { fg = surface0, bg = base })
hl("DiagnosticError", { fg = red })
hl("DiagnosticWarn", { fg = yellow })
hl("DiagnosticInfo", { fg = sky })
hl("DiagnosticHint", { fg = lavender })
hl("DiffAdd", { fg = green, bg = surface0 })
hl("DiffDelete", { fg = red, bg = surface0 })
hl("DiffChange", { bg = surface0 })
hl("DiffText", { fg = text, bg = selection })
hl("ErrorMsg", { fg = red })
hl("WarningMsg", { fg = yellow })
for _, pair in ipairs({
  { "@comment", "Comment" }, { "@string", "String" }, { "@number", "Number" }, { "@keyword", "Keyword" },
  { "@function", "Function" }, { "@type", "Type" }, { "@variable", "Identifier" }, { "@punctuation", "Delimiter" },
}) do
  hl(pair[1], { link = pair[2] })
end
