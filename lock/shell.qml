pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "LockModel.js" as Model
import "ThemeModel.js" as ThemeModel

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

  // The palette (ADR 0037): Subarchy's default under the user's file, which
  // Pult writes; read once at start, since the program lives for one lock.
  // ThemeModel.js is the shell's copy: Quickshell refuses imports outside
  // the program's directory, and `make shell-index-check` keeps them equal.
  readonly property string systemPalette: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/theme/palette.json"
  readonly property string userPalette: Quickshell.env("HOME") + "/.config/subcult/theme/palette.json"
  property var fallback: ({})
  property var user: ({})
  readonly property var theme: ThemeModel.tokens(user, fallback)

  function colorsOf(text) {
    if (text.trim() === "")
      return {}
    try {
      const doc = JSON.parse(text)
      return doc && typeof doc.colors === "object" && doc.colors !== null ? doc.colors : {}
    } catch (e) {
      console.warn("subcult lock: palette is not valid JSON:", e.message)
      return {}
    }
  }

  FileView {
    path: root.systemPalette
    blockLoading: true
    printErrors: false
    onLoaded: root.fallback = root.colorsOf(text())
  }

  FileView {
    path: root.userPalette
    blockLoading: true
    printErrors: false
    onLoaded: root.user = root.colorsOf(text())
  }

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

  // Once unlocked the program exits: on the compositor's word, or shortly
  // after asking, since a compositor that never confirmed the lock (secure
  // stays false, as under a headless sway) does not answer the unlock.
  function finish() {
    if (!quit.running)
      quit.start()
  }

  Timer {
    id: quit
    interval: 300
    onTriggered: Qt.quit()
  }

  Timer {
    id: hardExit
    interval: 3000
    onTriggered: Qt.exit(0)
  }

  WlSessionLock {
    id: lock
    locked: true
    onLockedChanged: {
      if (!locked)
        root.finish()
    }

    WlSessionLockSurface {
      id: surface
      color: root.theme.base || "#100B19"

      LockView {
        anchors.fill: parent
        lockState: root.lockState
        theme: root.theme
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
        hardExit.start()
        root.finish()
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
        attempts: root.lockState.attempts, message: root.lockState.message, typed: root.lockState.password.length,
        base: String(root.theme.base || "")
      })
    }
  }
}
