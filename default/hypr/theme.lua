-- Theme colours for the compositor (ADR 0037). These are the subcult-minimal
-- defaults; Theme Tender owns ~/.config/subcult/theme/hyprland.lua and, when
-- that file exists, it runs last and wins.

local active = "rgb(8F4BC8)" -- mauve
local inactive = "rgb(1F1830)" -- surface0

hl.config({
  general = {
    col = { active_border = active, inactive_border = inactive },
  },
  group = {
    col = { border_active = active, border_inactive = inactive },
    groupbar = { gradients = false },
  },
})

local user_theme = os.getenv("HOME") .. "/.config/subcult/theme/hyprland.lua"
local f = io.open(user_theme, "r")
if f then
  f:close()
  dofile(user_theme)
end
