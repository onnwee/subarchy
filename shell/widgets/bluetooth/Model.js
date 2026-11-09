.pragma library
// Bluetooth lists and the panel-owned pairing helper's private messages.

function paired(list) {
  const out = (list || []).filter(d => d && (d.paired || d.bonded))
  out.sort((a, b) => Number(!!b.connected) - Number(!!a.connected) || label(a).localeCompare(label(b)))
  return out
}

function nearby(list) {
  return (list || []).filter(d => d && typeof d === "object" && !d.paired && !d.bonded && label(d) !== "")
    .sort((a, b) => label(a).localeCompare(label(b)))
}

function label(d) {
  return String((d && (d.name || d.deviceName)) || d && d.address || "")
}

// BluetoothDeviceState values as Quickshell numbers them.
function stateText(d) {
  if (!d)
    return ""
  if (d.pairing)
    return "Pairing…"
  switch (Number(d.state)) {
  case 1: return "Connected"
  case 2: return "Disconnecting…"
  case 3: return "Connecting…"
  }
  return "Not connected"
}

// Battery as a percentage when the device reports one.
function batteryText(d) {
  if (!d || !d.batteryAvailable)
    return ""
  const b = Number(d.battery) || 0
  return Math.round(b <= 1 ? b * 100 : b) + " %"
}

// A click's action: connect when disconnected, disconnect when connected,
// nothing while changing.
function action(d) {
  if (d && d.pairing)
    return ""
  const s = Number(d && d.state)
  if (s === 2 || s === 3)
    return ""
  return d && d.connected ? "disconnect" : "connect"
}

function pairingEvent(line) {
  let doc
  try { doc = JSON.parse(line) } catch (e) { return null }
  if (!doc || typeof doc !== "object" || Array.isArray(doc))
    return null
  if (["ready", "pairing", "clear"].indexOf(doc.event) >= 0)
    return doc
  if (doc.event === "error" || doc.event === "result")
    return typeof doc.message === "string" && (doc.event !== "result" || typeof doc.ok === "boolean") ? doc : null
  if (doc.event !== "prompt" || !Number.isInteger(doc.id) || doc.id < 1)
    return null
  if (["pin", "passkey", "confirmation", "authorization", "service", "display-pin", "display-passkey"].indexOf(doc.kind) < 0)
    return null
  if (["confirmation", "display-passkey"].indexOf(doc.kind) >= 0 && (typeof doc.code !== "string" || !/^[0-9]{6}$/.test(doc.code)))
    return null
  if (doc.kind === "display-pin" && (typeof doc.code !== "string" || doc.code.length < 1 || doc.code.length > 16))
    return null
  return doc
}

function promptText(request, name) {
  if (!request)
    return ""
  switch (request.kind) {
  case "pin": return "Enter the PIN supplied with " + name + "."
  case "passkey": return "Enter the passkey shown on " + name + "."
  case "confirmation": return "Does this code match on " + name + "?"
  case "authorization": return "Allow pairing with " + name + "?"
  case "service": return "Allow a Bluetooth connection to " + name + "?"
  default: return "Type this code on " + name + ", then press Enter on that device."
  }
}
