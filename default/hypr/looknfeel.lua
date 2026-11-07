-- Look and feel: the flat subcult-minimal profile (ADR 0037, ADR 0054).
-- Opaque windows, no gaps, rounding, blur, shadows, dimming or animations,
-- solid 1 px borders. Colours come from theme.lua.

hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    border_size = 1,
    resize_on_border = true,
    layout = "dwindle",
  },

  decoration = {
    rounding = 0,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    fullscreen_opacity = 1.0,
    dim_inactive = false,
    shadow = { enabled = false },
    blur = { enabled = false },
  },

  animations = {
    enabled = false,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = "rgb(100B19)",
    force_default_wallpaper = 0,
    animate_manual_resizes = false,
    animate_mouse_windowdragging = false,
  },
})

require("default.hypr.theme")
