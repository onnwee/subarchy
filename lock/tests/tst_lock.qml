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
