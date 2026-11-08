.pragma library
// The network panel's lists (shell stage 2, issue #84). Networks come from
// Quickshell.Networking (NetworkManager over D-Bus): the connected one
// first, then the known ones, then by signal, each name once.

// WifiSecurityType values as Quickshell numbers them.
const SECURITY = ["WPA3 Suite B", "WPA3", "WPA2 Enterprise", "WPA2", "WPA Enterprise", "WPA", "WEP", "WEP", "LEAP", "OWE", "Open", "Unknown"]

function securityText(security) {
  return SECURITY[Number(security)] || "Unknown"
}

// A network the user can join by clicking: known, open, or OWE.
function joinable(n) {
  if (!n)
    return false
  if (n.known)
    return true
  const s = Number(n.security)
  return s === 9 || s === 10
}

// A new network that takes a pre-shared key (the password field applies).
function needsPassword(n) {
  if (!n || n.known)
    return false
  const s = Number(n.security)
  return s === 1 || s === 3 || s === 5 || s === 6 || s === 7
}

// Sorted for the list: connected, known, then signal; one row per name
// (the strongest access point), nameless networks dropped.
function sortNetworks(list) {
  const seen = {}
  const out = []
  for (const n of list || []) {
    if (!n || !n.name)
      continue
    const prev = seen[n.name]
    if (!prev || (n.connected && !prev.connected) || (!prev.connected && Number(n.signalStrength) > Number(prev.signalStrength))) {
      if (prev)
        out.splice(out.indexOf(prev), 1)
      seen[n.name] = n
      out.push(n)
    }
  }
  out.sort((a, b) => Number(b.connected) - Number(a.connected) || Number(!!b.known) - Number(!!a.known)
    || Number(b.signalStrength) - Number(a.signalStrength) || a.name.localeCompare(b.name))
  return out
}

// ConnectionState values as Quickshell numbers them.
function stateText(n) {
  if (!n)
    return ""
  switch (Number(n.state)) {
  case 1: return "Connecting…"
  case 2: return "Connected"
  case 3: return "Disconnecting…"
  }
  return n.known ? "Saved" : ""
}

// Signal as a percentage for the row.
function signalText(strength) {
  const s = Number(strength) || 0
  return Math.round(s <= 1 ? s * 100 : s) + " %"
}
