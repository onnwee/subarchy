pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// PAM must execute outside the multithreaded renderer: PamContext's fork
// can inherit a held libc mutex (#211). Each start owns a fresh helper;
// retired workers cannot report a result into a later authentication.
QtObject {
  id: root
  property string config: "subcult-lock"
  property string configDirectory: "/etc/pam.d"
  readonly property string helper: Quickshell.env("SUBCULT_LOCK_PAM_HELPER") || "/usr/lib/subcult/pam-helper"
  property bool active: false
  property bool responseRequired: false
  property string message: ""
  property bool messageIsError: false
  property var worker: null
  signal completed(int result)
  signal error(int error)
  signal pamMessage()

  function start() {
    if (active)
      return false
    worker = launcher.createObject(root)
    active = true
    worker.running = true
    return true
  }

  function abort() {
    const old = worker
    worker = null
    active = false
    responseRequired = false
    message = ""
    messageIsError = false
    if (old) {
      old.running = false
      old.destroy()
    }
  }

  function respond(response) {
    if (!active || !responseRequired)
      return
    worker.write(JSON.stringify({ response: response }) + "\n")
    responseRequired = false
  }

  function received(child, data) {
    if (worker !== child)
      return
    try {
      const frame = JSON.parse(data)
      if (child.result !== -1)
        throw new Error("data after result")
      if (frame.event === "result" && [0, 1, 2, 3].includes(frame.result)) {
        child.result = frame.result
      } else if (frame.event === "message" && [1, 2, 3, 4].includes(frame.style) && typeof frame.text === "string") {
        message = frame.text
        messageIsError = frame.style === 3
        responseRequired = frame.style === 1 || frame.style === 2
        pamMessage()
      } else {
        throw new Error("invalid helper frame")
      }
    } catch (_error) {
      abort()
      error(2)
      completed(PamResult.Error)
    }
  }

  function ended(child, exitCode, exitStatus) {
    if (worker !== child)
      return
    const result = exitCode === 0 && exitStatus === 0 && child.result !== -1 ? child.result : PamResult.Error
    abort()
    if (result === PamResult.Error)
      error(2)
    completed(result)
  }

  property Component launcher: Component {
    Process {
      id: child
      property int result: -1
      command: [root.helper, root.config, root.configDirectory]
      stdinEnabled: true
      stdout: SplitParser { onRead: data => root.received(child, data) }
      // Helper failures expose only a result code; never retain stderr.
      stderr: SplitParser { onRead: _data => {} }
      onExited: (exitCode, exitStatus) => root.ended(child, exitCode, exitStatus)
      // FailedToStart has no exited signal in Quickshell 0.3.2.
      onRunningChanged: if (!running) root.ended(child, -1, 1)
    }
  }
}
