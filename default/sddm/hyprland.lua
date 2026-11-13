-- Hyprland config for the SDDM Wayland greeter (ADR 0030). SDDM starts the
-- greeter once this compositor is up. It runs as the sddm user, so it reads
-- only system files.

-- The layout and its variant, as the session reads them
-- (default/hypr/input.lua): the password is typed under the same keys here.
local layout, variant = "us", ""
local file = io.open("/etc/vconsole.conf", "r")
if file then
  for line in file:lines() do
    layout = line:match("^%s*XKBLAYOUT%s*=%s*\"?([^\"%s]+)") or layout
    variant = line:match("^%s*XKBVARIANT%s*=%s*\"?([^\"%s]+)") or variant
  end
  file:close()
end

hl.env("XCURSOR_THEME", "subcult-cursor")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "subcult-cursor")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
  input = { kb_layout = layout, kb_variant = variant },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = "rgb(100B19)",
    force_default_wallpaper = 0,
  },
  animations = { enabled = false },
  -- The greeter runs Hyprland as sddm too: no update or donation window.
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
