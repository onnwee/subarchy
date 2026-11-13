.pragma library
// TOZO HT3 headphones: which Bluetooth device is one, and the lines of the
// panel's helper, `subcult ht3 watch <address>` (one JSON object each).

const modes = {
  normal: "Normal",
  anc: "Noise cancelling",
  transparency: "Transparency",
  wind: "Wind",
  leisure: "Leisure",
  adaptive: "Adaptive",
  unknown: "Unknown"
}

// An HT3 by its BlueZ alias or remote name: one that contains both "HT3"
// and "TOZO" in any case ("TOZO HT3", "TOZO-HT3", "TOZOHT3"), the rule of
// the owner's omarchy-plugin-ht3.
function isHt3(d) {
  if (!d || typeof d !== "object")
    return false
  return [d.name, d.deviceName].some(n => typeof n === "string" && /ht3/i.test(n) && /tozo/i.test(n))
}

function label(d) {
  return String((d && (d.name || d.deviceName)) || (d && d.address) || "HT3")
}

// The connected HT3 the widget and panel follow: the first by name when
// there are several, so the choice does not move around.
function connected(list) {
  const found = (list || []).filter(d => isHt3(d) && d.connected && typeof d.address === "string" && d.address !== "")
  found.sort((a, b) => label(a).localeCompare(label(b)) || a.address.localeCompare(b.address))
  return found.length > 0 ? found[0] : null
}

// A helper line, checked; null when it is not one the helper sends.
function event(line) {
  let doc
  try { doc = JSON.parse(line) } catch (e) { return null }
  if (!doc || typeof doc !== "object" || Array.isArray(doc))
    return null
  switch (doc.event) {
  case "connected":
    return { event: "connected" }
  case "state": {
    const out = { event: "state", battery: -1, mode: "" }
    if (doc.battery !== undefined) {
      if (!Number.isInteger(doc.battery) || doc.battery < 0 || doc.battery > 100)
        return null
      out.battery = doc.battery
    }
    if (doc.mode !== undefined) {
      if (typeof doc.mode !== "string" || !Object.prototype.hasOwnProperty.call(modes, doc.mode))
        return null
      out.mode = doc.mode
    }
    return out
  }
  case "error":
    return typeof doc.message === "string" && doc.message !== "" ? { event: "error", message: doc.message } : null
  }
  return null
}

function modeText(mode) {
  return Object.prototype.hasOwnProperty.call(modes, mode) ? modes[mode] : ""
}

function batteryText(battery) {
  return Number.isInteger(battery) && battery >= 0 ? battery + " %" : ""
}

// BlueZ's own battery reading (Battery1), when the headset reports one;
// -1 otherwise. Quickshell gives it as 0..1.
function bluezBattery(d) {
  if (!d || !d.batteryAvailable)
    return -1
  const b = Number(d.battery) || 0
  return Math.round(b <= 1 ? b * 100 : b)
}
