.pragma library
// Notification history and popup rules (shell and look design). History
// keeps plain records (not live Notification objects), newest first.

function push(history, entry, cap) {
  return [entry].concat(history || []).slice(0, cap)
}

// Text from any app or web page, as plain text: entities decoded once
// (named and numeric), tags and comments stripped, whitespace collapsed,
// cut to cap. A tag starts with a letter or a slash right after "<", so
// "a < b and c > d" keeps its middle.
// Caps: summary 200, body 2000, app name 64.
const NAMED = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " }

function plain(text, cap) {
  if (text === null || text === undefined)
    return ""
  let s = String(text).replace(/<!--[\s\S]*?-->|<\/?[a-zA-Z][^<>]*>/g, " ")
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

// The history with the record of id changed (a replaced notification). Ids
// start again at 1 with every shell start while the saved history stays, so
// older records can share one: the live notification's is the newest, the
// first in the list.
function updateRecord(history, id, fields) {
  let done = false
  return (history || []).map(e => {
    if (done || e.id !== id)
      return e
    done = true
    return Object.assign({}, e, fields)
  })
}

// Do-not-disturb holds back popups, except critical ones.
function shouldPopup(n, dnd) {
  return !dnd || n.urgency === "critical"
}

// The history without the record of id. With its time, only that record:
// one from an earlier session can have the same id.
function removeRecord(history, id, time) {
  return (history || []).filter(e => !(e.id === id && (time === undefined || e.time === time)))
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
    return Array.isArray(list)
      ? list.filter(e => e !== null && typeof e === "object" && !Array.isArray(e)).slice(0, cap)
      : []
  } catch (e) {
    return []
  }
}

// The history once the saved file is first read: the records that arrived
// before the read (newest first) in front of the saved ones, capped. A
// clear made before the read drops the saved records; mark-all-read made
// before it marks them read.
function mergeEarly(saved, early, cap, cleared, read) {
  const base = cleared ? [] : read ? markAllRead(saved) : (saved || [])
  return (early || []).concat(base).slice(0, cap)
}

// The action run when the notification itself is clicked.
function defaultAction(actions) {
  return (actions || []).find(a => a.identifier === "default") || null
}

// The actions shown as buttons.
function buttonActions(actions) {
  return (actions || []).filter(a => a.identifier !== "default")
}
