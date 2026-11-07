.pragma library
// Notification history and popup rules (shell and look design). History
// keeps plain records (not live Notification objects), newest first.

function push(history, entry, cap) {
  return [entry].concat(history || []).slice(0, cap)
}

// Do-not-disturb holds back popups, except critical ones.
function shouldPopup(n, dnd) {
  return !dnd || n.urgency === "critical"
}

function unread(history) {
  return (history || []).filter(e => !e.read).length
}

function markAllRead(history) {
  return (history || []).map(e => Object.assign({}, e, { read: true }))
}

// The saved history; anything unreadable is an empty history.
function restore(text, cap) {
  try {
    const list = JSON.parse(text)
    return Array.isArray(list) ? list.slice(0, cap) : []
  } catch (e) {
    return []
  }
}

// The action run when the notification itself is clicked.
function defaultAction(actions) {
  return (actions || []).find(a => a.identifier === "default") || null
}

// The actions shown as buttons.
function buttonActions(actions) {
  return (actions || []).filter(a => a.identifier !== "default")
}
