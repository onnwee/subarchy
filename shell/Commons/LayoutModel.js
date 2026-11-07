.pragma library
// Per-monitor bar layout, as sputnik's monitor-bar does it: Full on the
// primary output and the laptop panel, Minimal elsewhere.

function modeFor(outputName, cfg) {
  const c = cfg || {}
  if (c.primary && outputName === c.primary)
    return "full"
  if (String(outputName).indexOf("eDP") === 0)
    return "full"
  if (Array.isArray(c.full) && c.full.indexOf(outputName) >= 0)
    return "full"
  return "minimal"
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
