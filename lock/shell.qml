pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "LockModel.js" as Model

// Subarchy's lock screen (ADR 0036): its own Quickshell program, apart from
// the desktop shell, so a shell crash cannot unlock the session. It locks
// the session the moment it starts, shows the SUBCULT lockup and the clock
// on every output, opens the prompt on the first key, checks the password
// through PAM (/etc/pam.d/subcult-lock) and exits once unlocked. The status
// IPC answers the tests; nothing unlocks over IPC.
ShellRoot {
  id: root

  readonly property string pamConfig: Quickshell.env("SUBCULT_LOCK_PAM") || "subcult-lock"
  readonly property string pamDir: Quickshell.env("SUBCULT_LOCK_PAM_DIR") || "/etc/pam.d"
  property var lockState: Model.initial()

  // One key from any output's surface.
  function key(name, text) {
    const r = Model.key(root.lockState, name, text)
    root.lockState = r.state
    if (r.submit) {
      if (!auth.start()) {
        root.lockState = Model.failed(root.lockState, "The password check could not start.")
      }
    }
  }

  WlSessionLock {
    id: lock
    locked: true
    onLockedChanged: {
      if (!locked)
        Qt.quit()
    }

    WlSessionLockSurface {
      id: surface
      color: "#100B19"

      LockView {
        anchors.fill: parent
        lockState: root.lockState
        onKey: (name, text) => root.key(name, text)
      }
    }
  }

  PamContext {
    id: auth
    config: root.pamConfig
    configDirectory: root.pamDir
    onResponseRequiredChanged: {
      if (responseRequired)
        auth.respond(root.lockState.password)
    }
    onCompleted: (result) => {
      if (result === PamResult.Success) {
        root.lockState = Model.unlocked(root.lockState)
        lock.locked = false
      } else {
        root.lockState = Model.failed(root.lockState, Model.failureMessage(root.lockState.attempts + 1))
      }
    }
    onError: (error) => {
      root.lockState = Model.failed(root.lockState, "The password check failed (" + error + "). Try again.")
    }
  }

  IpcHandler {
    target: "subcult.lock"
    function status(): string {
      return JSON.stringify({
        locked: lock.locked, secure: lock.secure, prompt: root.lockState.prompt, checking: root.lockState.checking,
        attempts: root.lockState.attempts, message: root.lockState.message, typed: root.lockState.password.length
      })
    }
  }
}
