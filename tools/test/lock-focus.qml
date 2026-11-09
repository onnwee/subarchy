import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "lock"
import "lock/LockModel.js" as Model

ShellRoot {
  id: test
  property int phase: 0
  property int ticks: 0
  TestCase { id: keys; when: false }
  function check(value, message) {
    if (!value) { console.error("FAIL: " + message); Qt.exit(1) }
  }
  Window {
    id: window
    visible: true
    width: 900; height: 700
    color: "#100b19"
    LockView {
      id: view
      anchors.fill: parent
      onKey: (name, text) => { view.lockState = Model.key(view.lockState, name, text).state }
      onWake: view.lockState = Object.assign({}, view.lockState, {prompt:true})
    }
    Item { id: other; activeFocusOnTab: true }
  }
  Window { id: otherWindow; width: 100; height: 100 }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: {
      test.check(++test.ticks < 200, "timed out at phase " + test.phase)
      switch (test.phase) {
      case 0:
        other.forceActiveFocus()
        test.check(!view.activeFocus, "fixture did not remove focus")
        keys.mouseClick(view, 450, 350)
        test.check(view.activeFocus, "click did not restore keyboard focus")
        keys.keyClick(Qt.Key_A)
        test.check(view.lockState.password === "a", "typing after click")
        keys.keyClick(Qt.Key_Backspace)
        test.check(view.lockState.password === "", "Backspace after click")
        test.phase++
        break
      case 1:
        other.forceActiveFocus()
        keys.keyClick(Qt.Key_Tab)
        test.check(view.activeFocus, "Tab did not reach password handler")
        keys.keyClick(Qt.Key_B)
        test.check(view.lockState.password === "b", "typing after Tab")
        keys.keyClick(Qt.Key_Escape)
        test.check(view.lockState.password === "", "Escape must clear password")
        other.forceActiveFocus()
        otherWindow.visible = true
        otherWindow.requestActivate()
        test.phase++
        break
      case 2:
        if (!otherWindow.active) return
        window.requestActivate()
        test.phase++
        break
      case 3:
        if (!window.active) return
        test.check(view.activeFocus, "activation did not reclaim keyboard focus")
        keys.keyClick(Qt.Key_C)
        test.check(view.lockState.password === "c", "typing after activation")
        console.log("PASS: lock focus")
        Qt.quit()
        break
      }
    }
  }
}
