.pragma library
// Alt-Tab order: windows by how recently they were focused (all
// workspaces), then any never focused, in their own order.

function order(clients, history) {
  const open = clients || []
  const recent = (history || []).filter(a => open.indexOf(a) >= 0)
  return recent.concat(open.filter(a => recent.indexOf(a) < 0))
}

// Hyprland's own focus order for a client (`hyprctl clients -j`, 0 is the
// focused window), so windows focused before the shell started still sort
// by recency. A client without one sorts last.
function focusRank(o) {
  const v = o && o.focusHistoryID
  return typeof v === "number" && v >= 0 ? v : 1e9
}

// Hyprland toplevels ({ address, lastIpcObject }) to addresses, most
// recently focused first by focusRank.
function byFocus(toplevels) {
  return toplevels.slice()
    .sort((a, b) => focusRank(a.lastIpcObject) - focusRank(b.lastIpcObject))
    .map(t => t.address)
}

// Put the newly focused window first, keep at most cap entries.
function remember(history, address, cap) {
  if (!address)
    return history
  return [address].concat((history || []).filter(a => a !== address)).slice(0, cap)
}

function next(order, index, step) {
  if (!order || order.length === 0)
    return -1
  return ((index + step) % order.length + order.length) % order.length
}

// Where a switch starts: the window used before this one, or (going
// backwards) the oldest.
function start(order, step) {
  if (!order || order.length === 0)
    return -1
  if (order.length === 1)
    return 0
  return step > 0 ? 1 : order.length - 1
}
