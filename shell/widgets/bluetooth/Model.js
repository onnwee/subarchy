.pragma library
// The Bluetooth panel's list (shell stage 2, issue #84): the adapter's
// paired devices, connected first, then by name. Discovery is never
// started here; pairing new devices is for the settings tools.

function paired(list) {
  const out = (list || []).filter(d => d && (d.paired || d.bonded))
  out.sort((a, b) => Number(!!b.connected) - Number(!!a.connected) || label(a).localeCompare(label(b)))
  return out
}

function label(d) {
  return String((d && (d.name || d.deviceName)) || d && d.address || "")
}

// BluetoothDeviceState values as Quickshell numbers them.
function stateText(d) {
  if (!d)
    return ""
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
  const s = Number(d && d.state)
  if (s === 2 || s === 3)
    return ""
  return d && d.connected ? "disconnect" : "connect"
}
