.pragma library
// Fingerprint unlock (#93, ADR 0023 and 0036): the lock runs fprintd's PAM
// module in a check of its own beside the password's. Pure, so the probe,
// the retry pacing and the text are testable without a reader.
//
// Modes: "off" (no reader, no finger enrolled, or not known yet: nothing
// shows and no fingerprint check runs), "ready" (a check waits for a
// touch), "nomatch" (the last touch was not recognised; the check goes on),
// "unavailable" (the reader keeps failing at once; retries slow down).

// The probe runs `fprintd-list <user>` (D-Bus Manager.GetDevices and
// ListEnrolledFingers) only when the PAM service file is there and fprintd
// is installed, and prints "no" otherwise.
const PROBE = 'test -f "$1" && command -v fprintd-list >/dev/null 2>&1 || { echo no; exit 0; }; LC_ALL=C exec fprintd-list "${USER:-$(id -un)}" 2>&1'

// fprintd-list's answer: "yes" when a reader has a finger enrolled for the
// user, "no" when there is no reader or no finger, "unknown" when fprintd
// could not be asked (it is still starting, D-Bus failed). Unknown is asked
// again; only "yes" turns fingerprint unlock on.
function classifyProbe(text) {
  const s = String(text || "").trim()
  if (/^[ \t]*-[ \t]*#[0-9]+:/m.test(s))
    return "yes"
  if (s === "no" || /^No devices available/m.test(s) || /has no fingers enrolled/i.test(s))
    return "no"
  return "unknown"
}

// When to ask fprintd again after the n-th unknown answer: 2 s, doubling,
// at most a minute.
function probeRetryMs(n) {
  return Math.min(60000, 2000 * Math.pow(2, Math.max(0, n - 1)))
}

// A check that ends within this time never reached the reader (no device,
// a claim that failed); one that lasted longer timed out or did not match.
const FAST_ERROR_MS = 2000
const RETRY_MS = 250
const ERROR_RETRY_CAP_MS = 40000
const UNAVAILABLE_AFTER = 3

// A finished check that did not unlock: the next one starts at once after an
// ordinary miss or timeout, and ever later (1 s, doubling, up to 40 s) while
// checks keep failing at once, so a broken reader is not hammered.
function settle(streak, elapsedMs) {
  if (elapsedMs >= FAST_ERROR_MS)
    return { streak: 0, delayMs: RETRY_MS }
  const next = streak + 1
  return { streak: next, delayMs: Math.min(ERROR_RETRY_CAP_MS, 1000 * Math.pow(2, next - 1)) }
}

function isUnavailable(streak) {
  return streak >= UNAVAILABLE_AFTER
}

// What pam_fprintd said during a check. "Failed to match fingerprint" is a
// touch that was not recognised; "Place your finger on …" means the reader
// answers again. "Verification timed out" and the rest change nothing.
// These are pam_fprintd's English texts; in another language a miss keeps
// the "ready" line (lock/README.md).
function message(mode, text, isError) {
  if (mode === "off")
    return mode
  const s = String(text || "")
  if (isError && /failed to match/i.test(s))
    return "nomatch"
  if (!isError && mode === "unavailable" && /^(Place|Swipe) your/i.test(s))
    return "ready"
  return mode
}

// The line under the password field when nothing else is said there.
function hint(mode) {
  if (mode === "ready")
    return "Or touch the fingerprint reader"
  if (mode === "nomatch")
    return "Fingerprint not recognised. Try again."
  if (mode === "unavailable")
    return "The fingerprint reader is not answering. Use your password."
  return ""
}

// The line before the prompt opens.
function idleText(mode) {
  return mode === "off" ? "Press a key to unlock" : "Press a key or touch the reader to unlock"
}
