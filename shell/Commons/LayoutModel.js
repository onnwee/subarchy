.pragma library
// Per-monitor bar layout, as sputnik's monitor-bar does it: Full on the
// primary output and the laptop panel, Minimal elsewhere. When no primary
// is connected and there is no laptop panel, the first output is Full, so
// a desktop always has one full bar.

function isLaptop(name) {
  return String(name).indexOf("eDP") === 0
}

function modeFor(outputName, cfg, outputs) {
  const c = cfg || {}
  const all = Array.isArray(outputs) ? outputs : []
  if (c.primary && outputName === c.primary)
    return "full"
  if (isLaptop(outputName))
    return "full"
  if (Array.isArray(c.full) && c.full.indexOf(outputName) >= 0)
    return "full"
  const primaryConnected = !!c.primary && all.indexOf(c.primary) >= 0
  const laptopConnected = all.some(isLaptop)
  if (!primaryConnected && !laptopConnected && all.length > 0 && all[0] === outputName)
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
