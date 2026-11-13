import QtQuick
import QtTest
import "../theme" as Theme

// SDDM's public context, without a display manager, PAM or real credentials.
Item {
  id: fixture
  width: 1280
  height: 800
  property var config: ({})
  property var userModel: ({ lastUser: "tester" })
  property var sessionModel: ({ lastIndex: 0 })
  // SDDM's KeyboardModel: it knows Caps Lock only under X11.
  property QtObject keyboard: QtObject { property bool capsLock: false }

  QtObject {
    id: sddm
    property string hostName: "sputnik-test"
    property int calls: 0
    property string lastUser: ""
    property string lastPassword: ""
    property int lastSession: -1
    signal informationMessage(string message)
    signal loginFailed()
    signal loginSucceeded()
    function login(user, password, session) {
      calls++
      lastUser = user
      lastPassword = password
      lastSession = session
    }
  }

  Theme.Main { id: greeter; anchors.fill: parent }

  TestCase {
    name: "SubarchyGreeter"
    when: windowShown

    property var user: null
    property var password: null
    property var submit: null
    property var scroller: null

    function initTestCase() {
      user = findChild(greeter, "userField")
      password = findChild(greeter, "passwordField")
      submit = findChild(greeter, "signInButton")
      scroller = findChild(greeter, "loginScroller")
      verify(user && password && submit && scroller)
      compare(user.text, "tester")
      compare(password.echoMode, TextInput.Password)
    }

    function init() {
      fixture.width = 1280
      fixture.height = 800
      greeter.authenticating = false
      greeter.startingSession = false
      greeter.message = ""
      greeter.pamLines = []
      greeter.afterPamText = false
      greeter.capsGuess = false
      greeter.capsKnown = false
      fixture.keyboard.capsLock = false
      fixture.config = ({})
      sddm.calls = 0
      sddm.lastPassword = ""
      user.text = "tester"
      password.text = ""
      password.forceActiveFocus()
      scroller.contentY = 0
      wait(30)
    }

    function capture(path) {
      let finished = false
      let saved = false
      verify(greeter.grabToImage(result => {
        saved = result.saveToFile(path)
        finished = true
      }))
      tryVerify(() => finished)
      verify(saved)
    }

    // Everything on screen without scrolling, centred, inside the window.
    function checkFits() {
      compare(scroller.contentHeight, scroller.height, "the form needs no scrolling")
      for (const item of [findChild(greeter, "brandLogo"), user, password, submit]) {
        const p = item.mapToItem(greeter, 0, 0)
        verify(p.x >= 0 && p.x + item.width <= greeter.width && p.y >= 0 && p.y + item.height <= greeter.height,
               item.objectName + " is inside the window")
      }
      const p = user.mapToItem(greeter, 0, 0)
      fuzzyCompare(p.x + user.width / 2, greeter.width / 2, 1)
    }

    function test_tabOrderAndLabels() {
      user.forceActiveFocus()
      verify(findChild(greeter, "userLabel").font.bold, "the focused field's label stands out")
      verify(!findChild(greeter, "passwordLabel").font.bold)
      compare(user.background.border.width, 2)
      compare(password.background.border.width, 1)
      keyClick(Qt.Key_Tab)
      verify(password.activeFocus)
      verify(findChild(greeter, "passwordLabel").font.bold)
      keyClick(Qt.Key_Tab)
      verify(submit.activeFocus)
      keyClick(Qt.Key_Tab)
      verify(user.activeFocus)
      keyClick(Qt.Key_Backtab)
      verify(submit.activeFocus)
      keyClick(Qt.Key_Backtab)
      verify(password.activeFocus)
    }

    function test_returnOnButton() {
      password.text = "fixture-password"
      submit.forceActiveFocus()
      keyClick(Qt.Key_Return)
      compare(sddm.calls, 1)
      compare(sddm.lastPassword, "fixture-password")
    }

    function test_escapeClears() {
      keyClick("x")
      keyClick("y")
      compare(password.text, "xy", "typing reaches the field")
      greeter.message = "That password didn't work. Try again."
      keyClick(Qt.Key_Escape)
      compare(password.text, "")
      compare(greeter.message, "")
      verify(!findChild(greeter, "loginError").visible)
      password.text = "fixture-password"
      submit.forceActiveFocus()
      keyClick(Qt.Key_Escape)
      compare(password.text, "")
      verify(password.activeFocus, "Escape returns to the password")
      // In the user field Escape puts back the last user and stays there.
      password.text = "fixture-password"
      user.forceActiveFocus()
      user.text = "someone-else"
      greeter.message = "That password didn't work. Try again."
      keyClick(Qt.Key_Escape)
      compare(user.text, "tester")
      verify(user.activeFocus, "focus stays in the user field")
      compare(password.text, "fixture-password", "the password is left alone")
      compare(greeter.message, "")
      password.forceActiveFocus()
      password.text = "fixture-password"
      greeter.login()
      greeter.clear()
      compare(password.text, "fixture-password", "nothing clears while the check runs")
      sddm.loginFailed()
    }

    function test_capsLock() {
      const hint = findChild(greeter, "capsLockHint")
      verify(!hint.visible)
      // Caps Lock may already be on (from the disk unlock prompt); the key
      // alone cannot say which way it went, so the tag waits for a letter.
      keyClick(Qt.Key_CapsLock)
      verify(!greeter.capsLock && !hint.visible, "no guess before a letter")
      keyClick(Qt.Key_CapsLock)
      verify(!greeter.capsLock && !hint.visible)
      fixture.keyboard.capsLock = true
      verify(hint.visible, "SDDM's own Caps Lock state shows")
      fixture.keyboard.capsLock = false
      verify(!hint.visible)
      // Under Wayland: an upper-case letter without Shift means Caps Lock.
      keyClick("A")
      verify(greeter.capsLock && hint.visible)
      compare(password.text, "A")
      wait(30)
      capture("greeter-caps.png")
      keyClick("b")
      verify(!greeter.capsLock)
      keyClick("c", Qt.ShiftModifier)
      verify(greeter.capsLock, "Shift with Caps Lock gives lower case")
      keyClick("1")
      verify(greeter.capsLock, "a digit says nothing")
      keyClick(Qt.Key_CapsLock)
      verify(!greeter.capsLock, "the Caps Lock key turns the hint off")
      keyClick(Qt.Key_CapsLock)
      verify(greeter.capsLock)
      // The key counts wherever focus is.
      submit.forceActiveFocus()
      keyClick(Qt.Key_CapsLock)
      verify(!greeter.capsLock, "Caps Lock on the button turns the hint off")
      keyClick(Qt.Key_CapsLock)
      verify(greeter.capsLock)
      password.forceActiveFocus()
      password.text = "fixture-password"
      greeter.login()
      verify(!hint.visible, "the hint gives way to the check")
      sddm.loginFailed()
    }

    function test_busyState() {
      password.text = "fixture-password"
      greeter.login()
      verify(!user.enabled && !password.enabled && !submit.enabled)
      compare(submit.contentItem.text, "Signing in…")
      wait(30)
      capture("greeter-busy.png")
      sddm.loginFailed()
      compare(submit.contentItem.text, "Sign in")
      verify(user.enabled && password.enabled && submit.enabled)
    }

    // 1280x600 is the smallest full layout; 1280x800 at scale 1.5 leaves
    // out the clock; 4K at scale 1 doubles the type and spacing.
    function test_screenSizes() {
      compare(greeter.unit, 1)
      verify(findChild(greeter, "clock").visible)
      checkFits()
      fixture.height = 600
      wait(50)
      verify(!greeter.compact && findChild(greeter, "clock").visible)
      checkFits()
      // faillock's two lines fit, and the form stays where it was.
      const logo = findChild(greeter, "brandLogo")
      const before = logo.mapToItem(greeter, 0, 0).y
      greeter.message = "The account is locked due to 10 failed logins. (2 minutes left to unlock)"
      wait(50)
      verify(findChild(greeter, "loginError").lineCount >= 2, "the faillock text takes two lines here")
      checkFits()
      compare(logo.mapToItem(greeter, 0, 0).y, before, "a message does not move the form")
      greeter.message = ""
      wait(50)
      compare(logo.mapToItem(greeter, 0, 0).y, before, "clearing it does not either")
      fixture.height = 599
      wait(50)
      verify(greeter.compact)
      fixture.width = 853
      fixture.height = 533
      wait(50)
      verify(greeter.compact && !findChild(greeter, "clock").visible)
      checkFits()
      fixture.width = 2560
      fixture.height = 1440
      wait(50)
      fuzzyCompare(greeter.unit, 1.8, 0.001)
      compare(user.height, 79)
      compare(user.font.pixelSize, 29)
      checkFits()
      tryCompare(findChild(greeter, "brandLogo"), "status", Image.Ready)
      wait(30)
      capture("greeter-large.png")
      fixture.width = 3840
      fixture.height = 2160
      wait(50)
      compare(greeter.unit, 2)
      compare(user.width, 720)
      checkFits()
    }

    function test_clock() {
      const time = findChild(greeter, "clockTime")
      let timer = null
      for (const o of greeter.resources)
        if (o.objectName === "clockTimer")
          timer = o
      verify(time && timer)
      verify(/^\d\d:\d\d$/.test(time.text), time.text)
      verify(timer.running)
      greeter.now = new Date(2001, 0, 2, 3, 4)
      compare(time.text, "03:04")
      fixture.height = 533
      wait(50)
      verify(greeter.compact && !timer.running, "no clock, no ticks")
      // An interval left from before the clock was hidden.
      timer.interval = 120000
      fixture.height = 800
      wait(50)
      verify(timer.running)
      verify(greeter.now.getFullYear() > 2001, "the clock catches up when it comes back")
      verify(timer.interval <= 60050, "the next tick is at the coming minute: " + timer.interval)
      compare(timer.interval, 60050 - (greeter.now.getTime() % 60000))
    }

    // theme.conf from subcult theme apply-system recolours the form.
    function test_configColours() {
      fixture.config = { accent: "#123456", border: "#654321", borderInactive: "#222222" }
      wait(30)
      verify(Qt.colorEqual(password.color, "#123456"), "the bullets take accent")
      verify(Qt.colorEqual(password.background.border.color, "#654321"), "the focused edge takes border")
      verify(Qt.colorEqual(user.background.border.color, "#222222"), "the other edge takes borderInactive")
    }

    function test_emptyUser() {
      user.text = " "
      verify(!submit.enabled)
      greeter.login()
      compare(sddm.calls, 0)
      verify(user.activeFocus)
    }

    function test_keyboardAndFailure() {
      user.forceActiveFocus()
      keyClick(Qt.Key_Tab)
      verify(password.activeFocus)
      user.text = " tester "
      password.text = "fixture-password"
      keyClick(Qt.Key_Return)
      compare(sddm.calls, 1)
      compare(sddm.lastUser, "tester")
      compare(sddm.lastPassword, "fixture-password")
      compare(sddm.lastSession, 0)
      verify(greeter.authenticating)
      verify(!user.enabled && !password.enabled && !submit.enabled)
      greeter.login()
      compare(sddm.calls, 1, "duplicate login while busy")
      sddm.loginFailed()
      compare(password.text, "")
      verify(password.activeFocus)
      verify(!greeter.authenticating)
      verify(findChild(greeter, "loginError").visible)
      verify(greeter.message.indexOf("password") >= 0)
      wait(30)
      capture("greeter-error.png")
    }

    // A wrong password as SDDM reports it: PAM's general result, then
    // loginFailed twice (the error, then the finished check).
    function test_wrongPasswordShowsTheGeneralLine() {
      password.text = "fixture-password"
      greeter.login()
      sddm.informationMessage("Authentication failure")
      sddm.loginFailed()
      verify(greeter.authenticating, "the check is not over until the second loginFailed")
      sddm.loginFailed()
      verify(!greeter.authenticating)
      compare(greeter.message, "That password didn't work. Try again.")
      password.text = "next"
      sddm.loginFailed()
      compare(password.text, "next", "a loginFailed after the attempt keeps what was typed since")
    }

    // PAM translates its general result; the greeter knows it by position.
    function test_translatedGeneralLine() {
      password.text = "fixture-password"
      greeter.login()
      sddm.informationMessage("Fehler bei der Authentifizierung")
      sddm.loginFailed()
      sddm.loginFailed()
      verify(!greeter.authenticating)
      compare(greeter.message, "That password didn't work. Try again.")
    }

    // faillock's lines arrive, each with a loginFailed, while PAM still runs;
    // the greeter shows them and stays busy until the check is over.
    function test_lockedAccountSaysSoAndForHowLong() {
      password.text = "fixture-password"
      greeter.login()
      sddm.informationMessage("The account is locked due to 10 failed logins.")
      sddm.loginFailed()
      verify(greeter.authenticating, "an early loginFailed does not end the attempt")
      compare(greeter.message, "The account is locked due to 10 failed logins.")
      sddm.informationMessage("(2 minutes left to unlock)\n")
      sddm.loginFailed()
      verify(greeter.authenticating)
      sddm.informationMessage("Authentication failure")
      sddm.loginFailed()
      sddm.loginFailed()
      verify(!greeter.authenticating)
      verify(password.activeFocus)
      compare(findChild(greeter, "loginError").text,
              "The account is locked due to 10 failed logins. (2 minutes left to unlock)")
      wait(30)
      capture("greeter-locked.png")
      password.text = "fixture-password"
      greeter.login()
      compare(greeter.message, "", "a new attempt starts without the old text")
      sddm.loginFailed()
      compare(greeter.message, "That password didn't work. Try again.")
    }

    // If the finished check never reports, the form comes back on its own.
    function test_earlyFailureSettles() {
      password.text = "fixture-password"
      greeter.login()
      sddm.informationMessage("The account is locked due to 10 failed logins.")
      sddm.loginFailed()
      verify(greeter.authenticating)
      tryVerify(() => !greeter.authenticating, 12000)
      compare(greeter.message, "The account is locked due to 10 failed logins.")
    }

    function test_mouseAndSuccess() {
      password.text = "fixture-password"
      mouseClick(submit, submit.width / 2, submit.height / 2)
      compare(sddm.calls, 1)
      sddm.loginSucceeded()
      compare(password.text, "")
      verify(greeter.startingSession && greeter.authenticating)
      verify(!submit.enabled)
    }

    function test_narrowLayout() {
      fixture.width = 320
      fixture.height = 480
      wait(50)
      verify(greeter.compact)
      compare(user.width, 272)
      password.forceActiveFocus()
      keyClick(Qt.Key_Tab)
      verify(submit.activeFocus)
      wait(30)
      const point = submit.mapToItem(greeter, 0, 0)
      verify(point.x >= 0 && point.x + submit.width <= greeter.width)
      verify(point.y >= 0 && point.y + submit.height <= greeter.height)
      capture("greeter-narrow.png")
    }

    function test_wideArtwork() {
      verify(!greeter.compact)
      const logo = findChild(greeter, "brandLogo")
      tryCompare(logo, "status", Image.Ready)
      wait(30)
      // grabImage crops the window using logical coordinates at HiDPI.
      // The native item capture keeps the whole greeter at every scale;
      // greeter-test.sh checks the master mark's green pixels in this PNG.
      capture("greeter-wide.png")
    }
  }
}
