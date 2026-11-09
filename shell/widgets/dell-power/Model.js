.pragma library
// The Dell power widget's state (ADR 0021): what `subcult dell power state
// --json` reports, the names and glyph roles of the firmware profiles and
// charging modes, and the custom threshold arithmetic. Pure.

const PROFILES = { quiet: "Quiet", cool: "Cool", balanced: "Balanced", performance: "Performance" }
const MODES = { adaptive: "Adaptive", standard: "Standard", express: "Express", "primarily-ac": "Primarily AC", custom: "Custom" }

function parse(text) {
  try {
    const r = JSON.parse(text)
    return r && typeof r === "object" ? r : null
  } catch (e) {
    return null
  }
}

function visible(report) {
  return !!report && report.available === true
}

function activeId(list) {
  for (const item of list || [])
    if (item && item.active)
      return item.id
  return ""
}

function profileName(id) {
  return PROFILES[id] || id || ""
}

function modeName(id) {
  return MODES[id] || id || ""
}

// The power-profiles-daemon profile the firmware profile pairs with; the
// bar's glyph follows it.
function osProfile(id) {
  return id === "quiet" || id === "cool" ? "power-saver" : id === "performance" ? "performance" : "balanced"
}

function profiles(report) {
  return ((report && report.profiles) || []).map(p => ({ id: p.id, name: profileName(p.id), active: !!p.active }))
}

function modes(report) {
  const c = report && report.charging
  return ((c && c.modes) || []).map(m => ({ id: m.id, name: modeName(m.id), active: !!m.active }))
}

function custom(report) {
  const c = report && report.charging && report.charging.custom
  return c && typeof c === "object" ? c : null
}

function label(report) {
  return visible(report) ? profileName(activeId(report.profiles)) : ""
}

function tooltip(report) {
  if (!visible(report))
    return ""
  const parts = ["Dell: " + profileName(activeId(report.profiles))]
  const mode = activeId(modes(report))
  if (mode) {
    const c = custom(report)
    parts.push("charging " + modeName(mode).toLowerCase() + (mode === "custom" && c ? " " + c.start + "–" + c.stop + " %" : ""))
  }
  return parts.join(", ")
}

// One step of a custom threshold, kept in the firmware's range and on its
// step, with the stop at least 5 above the start. Returns { start, stop }.
function stepped(c, start, stop, which, direction) {
  const step = Number(c.step) || 5
  let s = Number(start), t = Number(stop)
  if (which === "start")
    s += direction * step
  else
    t += direction * step
  s = Math.min(Math.max(s, c.startMin), c.startMax)
  t = Math.min(Math.max(t, c.stopMin), c.stopMax)
  if (t < s + 5) {
    if (which === "start")
      t = Math.min(s + 5, c.stopMax)
    else
      s = Math.max(t - 5, c.startMin)
    if (t < s + 5)
      return { start: Number(start), stop: Number(stop) }
  }
  return { start: s, stop: t }
}
