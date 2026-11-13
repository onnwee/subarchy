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
