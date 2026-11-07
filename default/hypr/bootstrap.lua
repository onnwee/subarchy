-- Subarchy Hyprland bootstrap (ADR 0032, 0048).
-- The user's ~/.config/hypr/hyprland.lua runs this first. It lets require()
-- find the user's own modules in ~/.config and Subarchy's defaults in
-- /usr/share/subcult, so `require("default.hypr.subcult")` loads
-- /usr/share/subcult/default/hypr/subcult.lua.

local home = os.getenv("HOME")
local system = os.getenv("SUBCULT_PATH") or "/usr/share/subcult"

-- On `hyprctl reload` the Lua state survives; forget our modules so edits
-- to them take effect.
for module in pairs(package.loaded) do
  if module:match("^default%.hypr") or module:match("^hypr%.") then
    package.loaded[module] = nil
  end
end

package.path = home .. "/.config/?.lua;" .. system .. "/?.lua;" .. package.path
