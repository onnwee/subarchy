import QtQuick
import Quickshell
import Quickshell.Services.Pam

ShellRoot {
  id: root
  readonly property bool missing: Quickshell.env("PAM_TEST_MISSING") === "1"
  property var cases: missing ? ["missing"] : ["permit", "deny", "empty", "bad", "duplicate", "broken", "crashed", "ask", "cancel"]
  property var results: missing ? [PamResult.Error] : [PamResult.Success, PamResult.Failed, PamResult.Error, PamResult.Error,
    PamResult.Error, PamResult.Error, PamResult.Error, PamResult.Success, PamResult.Success]
  property int index: 0
  property int errors: 0
  property bool cancelled: false

  function check(ok, reason) {
    if (!ok) {
      console.error("FAIL: lock PAM " + reason)
      Qt.exit(1)
    }
  }
  function begin() {
    errors = 0
    session.config = cases[index]
    check(session.start(), "start")
    check(!session.start(), "accepted an overlapping start")
  }
  PamSession {
    id: session
    onResponseRequiredChanged: if (responseRequired) respond("dummy-password-é\nquoted \"text\"")
    onPamMessage: {
      if (config === "cancel") {
        root.cancelled = true
        abort()
        root.check(!active && !responseRequired, "cancel left state active")
        config = "permit"
        root.check(start(), "restart immediately after cancellation")
      }
    }
    onError: root.errors += 1
    onCompleted: result => {
      root.check(root.index < root.cases.length, "retired worker reported a late result")
      root.check(result === root.results[root.index], root.cases[root.index] + " result=" + result)
      root.check(root.errors === (result === PamResult.Error ? 1 : 0), "error signal count")
      root.check(!active && !responseRequired && message === "", "completion left state active")
      root.index += 1
      next.start()
    }
  }
  Timer {
    id: next
    interval: 200
    onTriggered: {
      if (root.index === root.cases.length) {
        root.check(root.missing || root.cancelled, "cancellation case did not run")
        console.info("PASS: lock PAM worker lifecycle")
        Qt.quit()
      } else {
        root.begin()
      }
    }
  }
  Timer { interval: 10000; running: true; onTriggered: { console.error("FAIL: lock PAM timeout"); Qt.exit(1) } }
  Component.onCompleted: begin()
}
