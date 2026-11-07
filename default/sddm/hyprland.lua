-- Hyprland config for the SDDM Wayland greeter (ADR 0030). SDDM starts the
-- greeter once this compositor is up. It runs as the sddm user, so it reads
-- only system files.

local layout = "us"
local file = io.open("/etc/vconsole.conf", "r")
if file then
  for line in file:lines() do
    local value = line:match("^%s*XKBLAYOUT%s*=%s*\"?([^\"%s]+)")
    if value then
      layout = value
    end
  end
  file:close()
end

hl.env("XCURSOR_THEME", "subcult-cursor")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "subcult-cursor")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
  input = { kb_layout = layout },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = "rgb(100B19)",
    force_default_wallpaper = 0,
  },
  animations = { enabled = false },
})
