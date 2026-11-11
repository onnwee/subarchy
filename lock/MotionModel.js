.pragma library
// The motion setting (rice port; ADR 0054): ~/.config/subcult/motion.json
// holds {"mode": "auto" | "on" | "off"}. `auto` is on while on AC and off on
// battery. The compositor reads the same file in default/hypr/looknfeel.lua
// at start and on a reload.

function mode(text) {
  try {
    const m = JSON.parse(text).mode
    return m === "on" || m === "off" ? m : "auto"
  } catch (e) {
    return "auto"
  }
}

function enabled(mode, onBattery) {
  return mode === "on" || (mode === "auto" && !onBattery)
}

// What the shell tells the compositor when the answer changes. Turning
// motion off sends only the gate, so gaps, borders and the layout a user set
// in their own Hyprland config stay as they are. Turning it on reloads the
// configuration: the theme's animations, blur and shadows come back, and so
// does everything the user's config sets.
const gateLua = "hl.config({ animations = { enabled = false }, "
  + "decoration = { blur = { enabled = false }, shadow = { enabled = false } } })"

function command(enabled) {
  return enabled ? ["hyprctl", "reload"] : ["hyprctl", "eval", gateLua]
}
