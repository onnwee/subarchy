.pragma library
// Per-monitor bar layout, as sputnik's monitor-bar does it: Full on the
// primary output and the laptop panel, Minimal elsewhere. When no primary
// is connected and there is no laptop panel, the first output is Full, so
// a desktop always has one full bar.
//
// An output is { name, description } (a bare name still works). The
// configured primary and full entries match a connector name exactly or
// part of the monitor's description (make, model, serial), so a monitor
// that moves between connectors on a dock keeps its bar.

function isLaptop(name) {
  return String(name).indexOf("eDP") === 0
}

// Hyprland's FALLBACK output (no real monitor) and nameless outputs get
// no bar and no overlay.
function isReal(name) {
  return typeof name === "string" && name !== "" && name !== "FALLBACK"
}

function asOutput(o) {
  if (o && typeof o === "object")
    return { name: String(o.name || ""), description: String(o.description || "") }
  return { name: String(o || ""), description: "" }
}

function matches(output, wanted) {
  const w = String(wanted || "").trim()
  if (w === "")
    return false
  if (output.name === w)
    return true
  return output.description !== "" && output.description.toLowerCase().indexOf(w.toLowerCase()) >= 0
}

function modeFor(output, cfg, outputs) {
  const c = cfg || {}
  const o = asOutput(output)
  const all = (Array.isArray(outputs) ? outputs : []).map(asOutput).filter(x => isReal(x.name))
  if (matches(o, c.primary))
    return "full"
  if (isLaptop(o.name))
    return "full"
  if (Array.isArray(c.full) && c.full.some(f => matches(o, f)))
    return "full"
  const primaryConnected = !!c.primary && all.some(x => matches(x, c.primary))
  const laptopConnected = all.some(x => isLaptop(x.name))
  if (!primaryConnected && !laptopConnected && all.length > 0 && all[0].name === o.name)
    return "full"
  return "minimal"
}

// A screen's description: Hyprland's for that output when it reports one
// ("make model serial"), else the screen's own model and serial.
function describe(screen, hyprMonitors) {
  const name = screen ? String(screen.name || "") : ""
  const hm = (hyprMonitors || []).find(m => m && m.name === name)
  const d = hm && hm.description ? String(hm.description) : ""
  if (d !== "")
    return d
  return [screen && screen.model, screen && screen.serialNumber].filter(x => x && String(x) !== "").map(String).join(" ")
}

function widgetsFor(layout, mode) {
  const l = layout || {}
  const pick = function (ids) {
    const list = Array.isArray(ids) ? ids : []
    if (mode !== "minimal")
      return list.slice()
    const keep = Array.isArray(l.minimal) ? l.minimal : []
    return list.filter(function (id) { return keep.indexOf(id) >= 0 })
  }
  return { left: pick(l.left), center: pick(l.center), right: pick(l.right) }
}
