.pragma library
// The motion setting (rice port; ADR 0054): ~/.config/subcult/motion.json
// holds {"mode": "auto" | "on" | "off"}. `auto` is on while on AC and off on
// battery. The compositor reads the same file in default/hypr/looknfeel.lua
// and the shell re-runs that file when the answer changes.

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

// The Lua the shell sends through `hyprctl eval`: re-run the look file, which
// applies the defaults, the theme and the motion gate again.
function evalLua(systemPath) {
  return "dofile([==[" + String(systemPath).replace(/\]==\]/g, "") + "/default/hypr/looknfeel.lua]==])"
}
