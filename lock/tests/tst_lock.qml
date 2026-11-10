import QtQuick
import QtTest
import "../LockModel.js" as Model

TestCase {
  name: "Lock"

  function type(state, chars) {
    for (const c of chars)
      state = Model.key(state, "text", c).state
    return state
  }

  function test_promptOpensOnFirstKey() {
    const s0 = Model.initial()
    verify(!s0.prompt)
    const s1 = Model.key(s0, "text", "a").state
    verify(s1.prompt)
    compare(s1.password, "a")
  }

  function test_returnOpensPromptWithoutSubmitting() {
    const r = Model.key(Model.initial(), "Return", "\r")
    verify(r.state.prompt)
    verify(!r.submit)
  }

  function test_backspaceEscapeReturn() {
    let s = type(Model.initial(), "secret")
    s = Model.key(s, "Backspace", "").state
    compare(s.password, "secre")
    s = Model.key(s, "Escape", "").state
    compare(s.password, "")
    verify(s.prompt, "escape keeps the prompt open")
    compare(Model.key(s, "Return", "\r").submit, false, "an empty password is not submitted")
    s = type(s, "pw")
    const r = Model.key(s, "Return", "\r")
    verify(r.submit)
    verify(r.state.checking)
    compare(Model.key(r.state, "text", "x").state.password, "pw", "nothing changes while checking")
  }

  // pam_unix holds a failure for about two seconds. A retry typed during
  // that wait must not lose its first characters: three failures reach
  // faillock's default limit.
  function test_typingDuringACheckIsKeptForTheRetry() {
    let s = Model.key(type(Model.initial(), "wrong"), "Return", "\r").state
    s = type(s, "rightx")
    s = Model.key(s, "Backspace", "").state
    compare(s.password, "wrong", "the password being checked is untouched")
    compare(Model.key(s, "Return", "\r").submit, false, "no second check while one runs")
    s = Model.failed(s, Model.failureMessage(1))
    compare(s.password, "right", "what was typed during the check is the next attempt")
    verify(!s.checking)
    let ok = Model.key(type(Model.initial(), "pw"), "Return", "\r").state
    ok = Model.unlocked(type(ok, "more"))
    compare(ok.password, "")
    compare(ok.typedAhead, "", "nothing typed is kept after the unlock")
    let cleared = Model.key(type(Model.initial(), "pw"), "Return", "\r").state
    cleared = Model.key(type(cleared, "abc"), "Escape", "").state
    compare(Model.failed(cleared, "x").password, "", "Escape during a check clears what was typed ahead")
  }

  function test_deleteAddsNothing() {
    compare(Model.keyName(16777223), "Delete")
    const s = type(Model.initial(), "pw")
    compare(Model.key(s, Model.keyName(16777223), "\u007f").state.password, "pw")
    compare(Model.key(s, "text", "\u007f").state.password, "pw", "U+007F is not a character of a password")
  }

  // The clock's timer: to just after the next minute, never shorter than
  // 50 ms. A SystemClock re-armed every millisecond through the hour that
  // repeats when daylight saving ends.
  function test_nextTickIsBoundedWhateverTheClockDid() {
    const minute = 1762754400000 // a whole minute
    compare(Model.nextTickMs(minute), 60050)
    compare(Model.nextTickMs(minute + 30000), 30050)
    compare(Model.nextTickMs(minute - 10), 60, "10 ms before the minute, plus the slack")
    verify(Model.nextTickMs(minute - 3600000 - 1) >= 50, "the clock went back an hour")
    verify(Model.nextTickMs(-5) >= 50)
    compare(Model.nextTickMs(NaN), 60050)
    compare(Model.nextTickMs("x"), 60050)
  }

  function test_controlCharactersIgnored() {
    const s = Model.key(Model.initial(), "text", "\u001b").state
    compare(s.password, "")
    compare(Model.key(Model.initial(), "text", "").state.password, "")
  }

  function test_failedAndUnlocked() {
    let s = Model.key(type(Model.initial(), "pw"), "Return", "\r").state
    s = Model.failed(s, Model.failureMessage(1))
    compare(s.password, "")
    compare(s.attempts, 1)
    verify(!s.checking)
    compare(s.message, "That did not work. Try again.")
    verify(Model.failureMessage(3).indexOf("3 attempts") > 0)
    const u = Model.unlocked(s)
    compare(u.password, "")
    compare(u.message, "")
  }

  function test_keyNames() {
    compare(Model.keyName(16777220), "Return")
    compare(Model.keyName(16777219), "Backspace")
    compare(Model.keyName(16777216), "Escape")
    compare(Model.keyName(65), "text")
  }

  function test_text() {
    compare(Model.bullets(3), "\u25CF\u25CF\u25CF")
    compare(Model.bullets(0), "")
    compare(Model.clockText(new Date(2026, 10, 8, 7, 5)), "07:05")
    compare(Model.clockText("nope"), "")
  }
}
