pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets/tailscale/Model.js" as Model

// Tailscale (ADR 0058), shared by the bar widget and its panel. The status
// comes from `tailscale status --json` when the widget's timer fires, when
// the panel opens and after each action, and every few seconds while a
// sign-in waits for the browser; the saved accounts (tailscale's
// profiles) from `tailscale switch --list --json` with it. Up, down,
// sign-in, adding and switching accounts and the exit node go through
// pkexec and the root helper (polkit action tv.subcult.tailscale, no
// password in the active session); no account is tailscaled's operator
// (ADR 0062).
Singleton {
  id: root

  property var status: null
  // The saved accounts, one of them selected: tailscale connects one at a
  // time.
  property var accounts: []
  // false once the command is missing: the widget leaves the bar.
  property bool installed: true
  property bool daemonDown: false
  // The last action's error, for the panel.
  property string error: ""
  // The sign-in link while tailscaled waits for the browser.
  property string loginUrl: ""
  // true while the sign-in adds another account (the helper's `add`).
  property bool adding: false
  // The account an add started from, to go back to when it is cancelled or fails.
  property string addingFrom: ""
  readonly property bool signingIn: (login.running && !login.cancelled) || root.loginUrl !== ""
  readonly property bool busy: action.running || login.running

  // A refresh asked for while a read is under way runs after it: that read
  // may have started before the change the caller wants to see.
  function refresh() {
    root.readStatus()
    root.readAccounts()
  }

  // One function each: Qt.callLater runs a function queued twice only once.
  function readStatus() {
    root.read(query)
  }

  function readAccounts() {
    root.read(accountsQuery)
  }

  function read(p) {
    if (p.running)
      p.again = true
    else
      p.running = true
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
    root.startSignIn(Model.helperCommand("login"), false)
  }

  // The helper's `add` does the same with `tailscale login`, which leaves
  // the account in use at once for a new, empty one.
  function addAccount() {
    const current = root.accounts.find(a => a.selected)
    root.startSignIn(Model.addAccountCommand(), true, current ? current.id : "")
  }

  function startSignIn(argv, add, from) {
    if (login.running)
      return
    root.error = ""
    root.loginUrl = ""
    root.adding = add
    root.addingFrom = from || ""
    login.cancelled = false
    login.command = argv
    login.running = true
  }

  // The helper runs as root and leaves by itself; this stops waiting and,
  // for an add, goes back to the account it started from (as a failed add
  // does).
  function cancelSignIn() {
    login.cancelled = true
    root.loginUrl = ""
    if (!login.running)
      root.switchBack()
  }

  function switchBack() {
    const id = root.addingFrom
    root.addingFrom = ""
    if (id !== "")
      root.switchAccount(id)
  }

  // Also ends a sign-in that waits for the browser.
  function switchAccount(id) {
    root.loginUrl = ""
    root.addingFrom = ""
    root.run(Model.switchCommand(id))
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
    if (root.status !== null && root.status.running && !login.running) {
      root.loginUrl = ""
      root.addingFrom = ""
    }
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
        root.cancelSignIn()
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
        Qt.callLater(root.readStatus)
      }
    }
  }

  Process {
    id: accountsQuery
    property bool again: false
    command: ["sh", "-c", "command -v tailscale >/dev/null || exit 127; exec tailscale switch --list --json"]
    stdout: StdioCollector {
      id: accountsOut
    }
    onExited: (code) => {
      root.accounts = code === 0 ? Model.parseAccounts(accountsOut.text) : []
      if (accountsQuery.again) {
        accountsQuery.again = false
        Qt.callLater(root.readAccounts)
      }
    }
  }

  Process {
    id: action
    stderr: StdioCollector {
      id: actionErr
    }
    onExited: (code) => {
      // run() cleared the error; a failed add's stays after the switch back.
      if (code !== 0)
        root.error = Model.errorText(actionErr.text) || "Tailscale did not change (exit " + code + ")"
      root.refresh()
    }
  }

  Process {
    id: login
    property bool cancelled: false
    stdout: StdioCollector {
      id: loginOut
    }
    stderr: StdioCollector {
      id: loginErr
    }
    onExited: (code) => {
      const url = Model.loginUrl(loginOut.text)
      if (login.cancelled) {
        root.switchBack()
        return
      }
      if (code !== 0) {
        // tailscale login has left the account in use by now.
        const error = Model.errorText(loginErr.text) || "Sign-in failed (exit " + code + ")"
        root.switchBack()
        root.error = error
      } else if (url !== "") {
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
        self: root.status ? root.status.self : null, peers: root.status ? root.status.peers.length : 0,
        accounts: root.accounts.length })
    }
  }
}
