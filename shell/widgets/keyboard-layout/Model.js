.pragma library
// The active layout's code ("US", "DE") from `hyprctl devices -j`. The
// keyboard is the one named in the last `activelayout` event when it is
// still there; otherwise the first device that is a keyboard rather than a
// power or lid button (Hyprland's `main` flag can sit on those); otherwise
// the first device. An index out of range falls back to the first layout.

const NOT_A_KEYBOARD = /power|lid|video-bus|sleep|button|hid-events|virtual/i

function pick(kbs, eventKeyboard) {
  const byEvent = eventKeyboard ? kbs.find(k => k.name === eventKeyboard) : null
  if (byEvent)
    return byEvent
  return kbs.find(k => !NOT_A_KEYBOARD.test(String(k.name || ""))) || kbs[0]
}

function fromDevices(json, eventKeyboard) {
  let d
  try {
    d = JSON.parse(json)
  } catch (e) {
    return ""
  }
  const kbs = (d && d.keyboards) || []
  if (kbs.length === 0)
    return ""
  const kb = pick(kbs, eventKeyboard)
  const layouts = String(kb.layout || "").split(",").map(s => s.trim()).filter(s => s !== "")
  if (layouts.length === 0)
    return ""
  const i = kb.active_layout_index >= 0 && kb.active_layout_index < layouts.length ? kb.active_layout_index : 0
  return layouts[i].toUpperCase()
}

// The keyboard an `activelayout` event names ("KEYBOARD,LAYOUT").
function eventKeyboard(data) {
  const s = String(data || "")
  const comma = s.indexOf(",")
  return comma < 0 ? s : s.slice(0, comma)
}
