.pragma library
// The lock screen's state (ADR 0036): what was typed, whether the prompt is
// open, whether a check runs, how many attempts failed. Pure, so the key
// handling and the messages are testable without a session.

function initial() {
  return { password: "", typedAhead: "", prompt: false, checking: false, attempts: 0, message: "", pamText: "" }
}

// Qt key codes the lock reacts to by name; anything else is text.
const KEYS = { 16777220: "Return", 16777221: "Enter", 16777219: "Backspace", 16777216: "Escape", 16777223: "Delete" }

function keyName(code) {
  return KEYS[code] || "text"
}

// One editing key applied to typed text. Delete arrives with U+007F as its
// text, which is not a character of a password.
function edit(typed, name, text) {
  if (name === "Backspace")
    return typed.slice(0, -1)
  if (name === "Escape")
    return ""
  if (name === "text" && typeof text === "string" && text !== "" && text.charCodeAt(0) >= 32 && text !== "\u007f")
    return typed + text
  return typed
}

// A key: returns { state, submit, cancel }. Text opens the prompt and adds to the
// password; Backspace removes one character; Escape clears; Return submits
// a non-empty password. While a check runs the password being checked does
// not change: what is typed is kept apart and becomes the next attempt if
// the check fails (a failure takes PAM about two seconds to report).
function key(state, name, text) {
  const s = Object.assign({}, state)
  if (s.checking) {
    // Escape gives up on a check that waits (a fingerprint reader, a
    // network login): the caller aborts it and the prompt is empty again.
    if (name === "Escape")
      return { state: Object.assign(s, { password: "", typedAhead: "", checking: false, message: "", pamText: "" }), submit: false, cancel: true }
    s.typedAhead = edit(s.typedAhead || "", name, text)
    return { state: s, submit: false }
  }
  s.prompt = true
  if (name === "Return" || name === "Enter") {
    if (s.password === "")
      return { state: s, submit: false }
    s.checking = true
    s.message = ""
    s.pamText = ""
    return { state: s, submit: true }
  }
  if (name === "Escape")
    s.message = ""
  s.password = edit(s.password, name, text)
  return { state: s, submit: false }
}

// Text PAM sent that is not a question (faillock's "The account is locked
// due to 3 failed logins", "Place your finger on the reader"). Shown while
// the check runs and, if it fails, instead of the general message. A module
// may send several lines; they are joined. Nothing outside a check counts.
function pamMessage(state, text) {
  const line = String(text || "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim()
  if (!state.checking || line === "")
    return state
  const all = ((state.pamText ? state.pamText + " " : "") + line).slice(0, 300)
  return Object.assign({}, state, { pamText: all, message: all })
}

// A failed check: the checked password is dropped, the attempt counted, the
// message shown; what PAM said itself wins over the message given here.
// What was typed during the check is the next attempt.
function failed(state, message) {
  return Object.assign({}, state, { password: state.typedAhead || "", typedAhead: "", checking: false, attempts: state.attempts + 1,
    message: state.pamText || message, pamText: "" })
}

function unlocked(state) {
  return Object.assign({}, state, { password: "", typedAhead: "", checking: false, message: "", pamText: "" })
}

function failureMessage(attempts) {
  return attempts === 1 ? "That did not work. Try again." : "That did not work (" + attempts + " attempts). Try again."
}

function bullets(n) {
  return "\u25CF".repeat(Math.max(0, Math.min(n, 32)))
}

// Milliseconds until the clock's next tick: just after the next minute by
// the given time, always between 50 and 60 050 whatever the clock did (a
// jump back, the repeated hour when daylight saving ends, garbage). The
// shell's ClockModel.js has the same rule.
function nextTickMs(nowMs) {
  const n = Number(nowMs)
  if (!isFinite(n))
    return 60050
  const into = ((n % 60000) + 60000) % 60000
  return Math.max(50, Math.min(60050, 60000 - into + 50))
}

function clockText(date) {
  const d = date instanceof Date ? date : new Date(date)
  return isNaN(d.getTime()) ? "" : ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
}
