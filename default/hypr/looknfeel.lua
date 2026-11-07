-- Look and feel. Colours here are the subcult-minimal placeholders until
-- Theme Tender renders the theme (ADR 0037); battery-first means no blur and
-- short animations (ADR 0054).

local accent = "rgba(8b5cf6ee)"
local inactive = "rgba(3f3f46aa)"

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 2,
    col = {
      active_border = accent,
      inactive_border = inactive,
    },
    resize_on_border = true,
    layout = "dwindle",
  },

  decoration = {
    rounding = 0,
    shadow = { enabled = false },
    blur = { enabled = false },
  },

  animations = {
    enabled = true,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = "rgb(0a0a0f)",
    force_default_wallpaper = 0,
  },
})
