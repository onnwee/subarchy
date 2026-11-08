.pragma library
// Notification history and popup rules (shell and look design). History
// keeps plain records (not live Notification objects), newest first.

function push(history, entry, cap) {
  return [entry].concat(history || []).slice(0, cap)
}

// Text from any app or web page, as plain text: entities decoded once
// (named and numeric), tags stripped, whitespace collapsed, cut to cap.
// Caps: summary 200, body 2000, app name 64.
const NAMED = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " }

function plain(text, cap) {
  if (text === null || text === undefined)
    return ""
  let s = String(text).replace(/<[^>]*>/g, " ")
  s = s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (m, e) => {
    if (e[0] === "#") {
      const code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)
      return code > 0 && code <= 0x10FFFF ? String.fromCodePoint(code) : ""
    }
    return Object.prototype.hasOwnProperty.call(NAMED, e) ? NAMED[e] : m
  })
  s = s.replace(/\s+/g, " ").trim()
  return cap > 0 && s.length > cap ? s.slice(0, cap) : s
}

// How long a popup stays, in ms: critical ones until dismissed (0); the
// app's own timeout within 2..30 s; 5 s when it gave none (-1 or 0).
function timeoutMs(expireTimeout, urgency) {
  if (urgency === "critical")
    return 0
  const t = Number(expireTimeout)
  if (!(t > 0))
    return 5000
  return Math.max(2000, Math.min(30000, t))
}

// The history with the record of id changed (a replaced notification).
function updateRecord(history, id, fields) {
  return (history || []).map(e => e.id === id ? Object.assign({}, e, fields) : e)
}

// Do-not-disturb holds back popups, except critical ones.
function shouldPopup(n, dnd) {
  return !dnd || n.urgency === "critical"
}

// The history without the record of id.
function removeRecord(history, id) {
  return (history || []).filter(e => e.id !== id)
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
