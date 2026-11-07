.pragma library
// The active layout's code ("US", "DE") from `hyprctl devices -j`: the
// main keyboard (or the first one), its comma-separated layouts and the
// active index. An index out of range falls back to the first layout.

function fromDevices(json) {
  let d
  try {
    d = JSON.parse(json)
  } catch (e) {
    return ""
  }
  const kbs = (d && d.keyboards) || []
  if (kbs.length === 0)
    return ""
  const kb = kbs.find(k => k.main) || kbs[0]
  const layouts = String(kb.layout || "").split(",").map(s => s.trim()).filter(s => s !== "")
  if (layouts.length === 0)
    return ""
  const i = kb.active_layout_index >= 0 && kb.active_layout_index < layouts.length ? kb.active_layout_index : 0
  return layouts[i].toUpperCase()
}
