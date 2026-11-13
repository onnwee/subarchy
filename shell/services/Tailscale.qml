pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets/tailscale/Model.js" as Model

// Tailscale (ADR 0058), shared by the bar widget and its panel. The status
// comes from `tailscale status --json` when the widget's timer fires, when
// the panel opens and after each action, and every few seconds while a
// sign-in waits for the browser. Up, down, sign-in and the exit node go
// through pkexec and the root helper (polkit action tv.subcult.tailscale,
// no password in the active session); no account is tailscaled's operator
// (ADR 0062).
Singleton {
  id: root

  property var status: null
  // false once the command is missing: the widget leaves the bar.
  property bool installed: true
  property bool daemonDown: false
  // The last action's error, for the panel.
  property string error: ""
  // The sign-in link while tailscaled waits for the browser.
  property string loginUrl: ""
  readonly property bool signingIn: (login.running && !login.cancelled) || root.loginUrl !== ""
  readonly property bool busy: action.running || login.running

  // A refresh asked for while a read is under way runs after it: that read
  // may have started before the change the caller wants to see.
  function refresh() {
    if (query.running)
      query.again = true
    else
      query.running = true
  }

  function run(argv) {
    if (action.running)
      return
    root.error = ""
    action.command = argv
    action.running = true
  }

  // Reconnects with the saved settings (`tailscale up` with no flags: any
  // flag would make it re-check every setting against its defaults).
  function up() {
    root.run(Model.helperCommand("up"))
  }

  // The helper's `login` starts `tailscale up`, prints the sign-in link and
  // leaves; tailscaled finishes the sign-in once the browser does, which
  // the status read every few seconds shows.
  function signIn() {
    if (login.running)
      return
    root.error = ""
    root.loginUrl = ""
    login.cancelled = false
    login.running = true
  }

  // The helper runs as root and leaves by itself; this only stops waiting.
  function cancelSignIn() {
    login.cancelled = true
    root.loginUrl = ""
  }

  function down() {
    root.run(Model.helperCommand("down"))
  }

  function setExitNode(peer) {
    root.run(Model.exitNodeCommand(peer))
  }

  function copy(text) {
    if (text !== "")
      Quickshell.clipboardText = text
  }

  // The file picker and the transfer belong to `subcult tailscale send`,
  // which reports the result as a notification.
  function send(peer) {
    Quickshell.execDetached(Model.sendCommand(peer))
  }

  function openLogin() {
    if (root.loginUrl !== "")
      Quickshell.execDetached(["uwsm-app", "--", "xdg-open", root.loginUrl])
  }

  onStatusChanged: {
    if (root.status !== null && root.status.running)
      root.loginUrl = ""
  }

  // While a sign-in waits for the browser, for ten minutes at most.
  Timer {
    id: loginPoll
    property real since: 0
    interval: 3000
    repeat: true
    running: root.loginUrl !== ""
    onRunningChanged: {
      if (loginPoll.running)
        loginPoll.since = Date.now()
    }
    onTriggered: {
      if (Date.now() - loginPoll.since > 600000)
        root.loginUrl = ""
      else
        root.refresh()
    }
  }

  Process {
    id: query
    property bool again: false
    // Exit 127 without the command, so a missing package hides the widget.
    command: ["sh", "-c", "command -v tailscale >/dev/null || exit 127; exec tailscale status --json"]
    stdout: StdioCollector {
      id: queryOut
    }
    stderr: StdioCollector {
      id: queryErr
    }
    onExited: (code) => {
      root.installed = code !== 127
      const s = Model.parse(queryOut.text)
      root.daemonDown = s === null && Model.daemonDown(queryErr.text)
      root.status = s
      if (query.again) {
        query.again = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: action
    stderr: StdioCollector {
      id: actionErr
    }
    onExited: (code) => {
      root.error = code === 0 ? "" : Model.errorText(actionErr.text) || "Tailscale did not change (exit " + code + ")"
      root.refresh()
    }
  }

  Process {
    id: login
    property bool cancelled: false
    command: Model.helperCommand("login")
    stdout: StdioCollector {
      id: loginOut
    }
    stderr: StdioCollector {
      id: loginErr
    }
    onExited: (code) => {
      const url = Model.loginUrl(loginOut.text)
      if (login.cancelled)
        return
      if (code !== 0)
        root.error = Model.errorText(loginErr.text) || "Sign-in failed (exit " + code + ")"
      else if (url !== "") {
        root.loginUrl = url
        root.openLogin()
      }
      root.refresh()
    }
  }

  IpcHandler {
    target: "subcult.tailscale"
    function refresh(): void { root.refresh() }
    function signIn(): void { root.signIn() }
    function cancelSignIn(): void { root.cancelSignIn() }
    function state(): string {
      return JSON.stringify({ installed: root.installed, daemonDown: root.daemonDown,
        state: root.status ? root.status.state : "", loginUrl: root.loginUrl,
        self: root.status ? root.status.self : null, peers: root.status ? root.status.peers.length : 0 })
    }
  }
}
