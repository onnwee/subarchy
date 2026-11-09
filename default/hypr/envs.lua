-- Session environment (ADR 0029: Wayland only, X11 apps through Xwayland).

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "subcult-cursor")
hl.env("HYPRCURSOR_THEME", "subcult-cursor")

hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
-- Qt apps take the GTK theme's colours, fonts and cursor (ADR 0037): the
-- palette Pult writes for GTK reaches Dolphin, Okular, Ark and VLC through
-- qt6-base's gtk3 platform theme, as on Omarchy.
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("SUBCULT_PATH", os.getenv("SUBCULT_PATH") or "/usr/share/subcult")

-- The cursor size chosen with `subcult cursor set`, if any.
local cursor_env = os.getenv("HOME") .. "/.config/subcult/cursor-env.lua"
local f = io.open(cursor_env, "r")
if f then
  f:close()
  local ok, err = pcall(dofile, cursor_env)
  if not ok then
    print("subcult cursor: " .. tostring(err))
  end
end
