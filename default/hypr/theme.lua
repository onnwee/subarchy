-- Theme colours for the compositor (ADR 0037). These are the subcult-minimal
-- defaults; Theme Tender owns ~/.config/subcult/theme/hyprland.lua and, when
-- that file exists, it runs right after these and overrides them.

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

-- A broken user theme must not stop the rest of the defaults (bindings,
-- autostart) from loading, so it runs protected and only logs its error.
local user_theme = os.getenv("HOME") .. "/.config/subcult/theme/hyprland.lua"
local f = io.open(user_theme, "r")
if f then
  f:close()
  local ok, err = pcall(dofile, user_theme)
  if not ok then
    print("subcult theme: " .. tostring(err))
  end
end
