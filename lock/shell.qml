pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pam
import Quickshell.Wayland
import "LockModel.js" as Model
import "ThemeModel.js" as ThemeModel
import "MotionModel.js" as MotionModel
import "FingerprintModel.js" as Fingerprint

// Subarchy's lock screen (ADR 0036): its own Quickshell program, apart from
// the desktop shell, so a shell crash cannot unlock the session. It locks
// the session the moment it starts, shows the SUBCULT lockup and the clock
// on every output, opens the prompt on the first key, checks the password
// through PAM (/etc/pam.d/subcult-lock) and exits once unlocked. Where
// fprintd has a finger enrolled for the user, a fingerprint check runs
// beside the password's (/etc/pam.d/subcult-lock-fingerprint); either one
// unlocks. The status IPC answers the tests; nothing unlocks over IPC.
ShellRoot {
  id: root

  readonly property string pamConfig: Quickshell.env("SUBCULT_LOCK_PAM") || "subcult-lock"
  readonly property string pamDir: Quickshell.env("SUBCULT_LOCK_PAM_DIR") || "/etc/pam.d"
  readonly property string fingerprintConfig: Quickshell.env("SUBCULT_LOCK_FINGERPRINT_PAM") || "subcult-lock-fingerprint"
  property var lockState: Model.initial()
  // Set once either check succeeds: nothing starts after that.
  property bool unlocking: false

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

  readonly property string systemArt: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/screensaver"
  readonly property string userArt: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/subcult/screensaver"
  property var systemLoops: []
  property var userLoops: []
  readonly property string artDir: userLoops.length ? userArt : systemArt
  readonly property var loops: userLoops.length ? userLoops : systemLoops
  readonly property int choice: Math.floor(Math.random() * 100000)
  readonly property string effect: loops.length ? loops[choice % loops.length] : ""
  // Battery always uses still art, even if motion is forced on.
  readonly property bool animate: !UPower.onBattery && MotionModel.enabled(MotionModel.mode(motion.text), UPower.onBattery)
  property int playing: 0

  function readLoops(text) {
    try {
      const doc = JSON.parse(text)
      return doc.schema === 1 && Array.isArray(doc.loops) ? doc.loops.filter(n => typeof n === "string" && /^[a-z0-9-]+$/.test(n)) : []
    } catch (e) {
      return []
    }
  }

  FileView {
    path: root.systemArt + "/index.json"
    blockLoading: true
    printErrors: false
    onLoaded: root.systemLoops = root.readLoops(text())
  }
  FileView {
    path: root.userArt + "/index.json"
    blockLoading: true
    printErrors: false
    onLoaded: root.userLoops = root.readLoops(text())
  }
  WatchedFile {
    id: motion
    path: Quickshell.env("HOME") + "/.config/subcult/motion.json"
  }

  function wake() {
    root.lockState = Object.assign({}, root.lockState, { prompt: true })
  }

  // One key from any output's surface.
  function key(name, text) {
    const r = Model.key(root.lockState, name, text)
    root.lockState = r.state
    if (r.cancel)
      auth.abort()
    if (r.submit) {
      if (!auth.start()) {
        root.lockState = Model.failed(root.lockState, "The password check could not start.")
      }
    }
  }

  // One check succeeded: stop the other, then unlock.
  function unlock(byFingerprint) {
    root.unlocking = true
    fingerprintRetry.stop()
    probeRetry.stop()
    if (!byFingerprint && fingerprintAuth.active)
      fingerprintAuth.abort()
    if (byFingerprint && auth.active)
      auth.abort()
    root.lockState = Model.unlocked(root.lockState)
    lock.locked = false
    hardExit.start()
    root.finish()
  }

  // Fingerprint unlock (#93, ADR 0023): a PAM check of its own, so the
  // password stack and its check stay as they are. It runs only once
  // fprintd says a reader has a finger enrolled for this user; without one
  // nothing shows and pam_fprintd never runs. A check that ends without a
  // match starts again; the password works the whole time.
  property string fingerprint: "off"
  property int fingerprintProbes: 0
  property int fingerprintStreak: 0
  property bool fingerprintRunning: false
  property double fingerprintStarted: 0

  Process {
    id: fingerprintProbe
    running: true
    command: ["sh", "-c", Fingerprint.PROBE, "sh", root.pamDir + "/" + root.fingerprintConfig]
    stdout: StdioCollector {
      onStreamFinished: root.probed(text)
    }
  }

  Timer {
    id: probeRetry
    onTriggered: fingerprintProbe.running = true
  }

  function probed(text) {
    if (root.unlocking)
      return
    const answer = Fingerprint.classifyProbe(text)
    if (answer === "yes") {
      root.fingerprint = "ready"
      root.startFingerprint()
    } else if (answer === "unknown") {
      probeRetry.interval = Fingerprint.probeRetryMs(++root.fingerprintProbes)
      probeRetry.start()
    }
  }

  function startFingerprint() {
    if (root.unlocking || root.fingerprint === "off" || root.fingerprintRunning)
      return
    root.fingerprintRunning = true
    root.fingerprintStarted = Date.now()
    if (!fingerprintAuth.start())
      root.fingerprintSettled()
  }

  // A check ended without unlocking: start the next one, paced.
  function fingerprintSettled() {
    if (!root.fingerprintRunning)
      return
    root.fingerprintRunning = false
    if (root.unlocking)
      return
    const r = Fingerprint.settle(root.fingerprintStreak, Date.now() - root.fingerprintStarted)
    root.fingerprintStreak = r.streak
    if (Fingerprint.isUnavailable(r.streak))
      root.fingerprint = "unavailable"
    fingerprintRetry.interval = r.delayMs
    fingerprintRetry.restart()
  }

  Timer {
    id: fingerprintRetry
    onTriggered: root.startFingerprint()
  }

  // "Not recognised" shows for a few seconds; the check is still running.
  Timer {
    id: nomatchClear
    interval: 4000
    onTriggered: {
      if (root.fingerprint === "nomatch")
        root.fingerprint = "ready"
    }
  }

  PamContext {
    id: fingerprintAuth
    config: root.fingerprintConfig
    configDirectory: root.pamDir
    // pam_fprintd asks nothing. A stack that asks for a password is not a
    // fingerprint stack: it gets no answer.
    onResponseRequiredChanged: {
      if (responseRequired) {
        fingerprintAuth.abort()
        root.fingerprintSettled()
      }
    }
    onPamMessage: {
      const mode = Fingerprint.message(root.fingerprint, message, messageIsError)
      if (mode === "nomatch")
        nomatchClear.restart()
      root.fingerprint = mode
    }
    onCompleted: (result) => {
      if (!root.fingerprintRunning)
        return
      if (result === PamResult.Success)
        root.unlock(true)
      else
        root.fingerprintSettled()
    }
    onError: root.fingerprintSettled()
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
        fingerprint: root.fingerprint
        theme: root.theme
        animate: root.animate
        video: root.effect ? "file://" + root.artDir + "/" + root.effect + ".webm" : ""
        still: root.effect ? "file://" + root.artDir + "/" + root.effect + ".png" : ""
        onWake: root.wake()
        onPlaybackChanged: (active) => root.playing += active ? 1 : -1
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
    onPamMessage: {
      if (!responseRequired)
        root.lockState = Model.pamMessage(root.lockState, message)
    }
    onCompleted: (result) => {
      // A check given up with Escape reports nothing.
      if (!root.lockState.checking)
        return
      if (result === PamResult.Success) {
        root.unlock(false)
      } else {
        root.lockState = Model.failed(root.lockState, Model.failureMessage(root.lockState.attempts + 1))
      }
    }
    onError: (error) => {
      if (!root.lockState.checking)
        return
      root.lockState = Model.failed(root.lockState, "The password check failed (" + error + "). Try again.")
    }
  }

  IpcHandler {
    target: "subcult.lock"
    function status(): string {
      return JSON.stringify({
        locked: lock.locked, secure: lock.secure, prompt: root.lockState.prompt, checking: root.lockState.checking,
        attempts: root.lockState.attempts, message: root.lockState.message, typed: root.lockState.password.length,
        base: String(root.theme.base || ""), screensaver: !root.lockState.prompt,
        motion: root.animate, playing: root.playing, effect: root.effect, artDir: root.artDir,
        fingerprint: root.fingerprint, fingerprintChecking: root.fingerprintRunning
      })
    }
  }
}
