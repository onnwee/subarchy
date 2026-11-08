-- Your Hyprland configuration. The installer copied this file to
-- ~/.config/hypr/hyprland.lua; Subarchy's updates never touch it (ADR 0048).
--
-- Subarchy's defaults load first, from /usr/share/subcult/default/hypr/.
-- Put your changes below them, for example:
--
--   hl.config({ general = { gaps_out = 4 } })
--   sub.bind("SUPER + B", "Browser", sub.launch("zen-browser"))
--   sub.bind("SUPER + ALT + U", "Update", sub.alias("up")) -- a launcher alias
--
-- Modules in ~/.config/hypr/ load with require("hypr.<name>").

dofile((os.getenv("SUBCULT_PATH") or "/usr/share/subcult") .. "/default/hypr/bootstrap.lua")
require("default.hypr.subcult")

-- Your overrides:
