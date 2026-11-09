.pragma library
// The lock screen's state (ADR 0036): what was typed, whether the prompt is
// open, whether a check runs, how many attempts failed. Pure, so the key
// handling and the messages are testable without a session.

function initial() {
  return { password: "", prompt: false, checking: false, attempts: 0, message: "" }
}

// Qt key codes the lock reacts to by name; anything else is text.
const KEYS = { 16777220: "Return", 16777221: "Enter", 16777219: "Backspace", 16777216: "Escape" }

function keyName(code) {
  return KEYS[code] || "text"
}

// A key: returns { state, submit }. Text opens the prompt and adds to the
// password; Backspace removes one character; Escape clears; Return submits
// a non-empty password. Nothing changes while a check runs.
function key(state, name, text) {
  const s = Object.assign({}, state)
  if (s.checking)
    return { state: s, submit: false }
  if (name === "Return" || name === "Enter") {
    if (s.password === "")
      return { state: s, submit: false }
    s.checking = true
    s.message = ""
    return { state: s, submit: true }
  }
  s.prompt = true
  if (name === "Backspace") {
    s.password = s.password.slice(0, -1)
  } else if (name === "Escape") {
    s.password = ""
    s.message = ""
  } else if (typeof text === "string" && text !== "" && text.charCodeAt(0) >= 32) {
    s.password += text
  }
  return { state: s, submit: false }
}

// A failed check: the password is dropped, the attempt counted, the message shown.
function failed(state, message) {
  return Object.assign({}, state, { password: "", checking: false, attempts: state.attempts + 1, message: message })
}

function unlocked(state) {
  return Object.assign({}, state, { password: "", checking: false, message: "" })
}

function failureMessage(attempts) {
  return attempts === 1 ? "That did not work. Try again." : "That did not work (" + attempts + " attempts). Try again."
}

function bullets(n) {
  return "\u25CF".repeat(Math.max(0, Math.min(n, 32)))
}

function clockText(date) {
  const d = date instanceof Date ? date : new Date(date)
  return isNaN(d.getTime()) ? "" : ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
}
