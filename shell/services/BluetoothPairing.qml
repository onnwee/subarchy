pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../widgets/bluetooth/Model.js" as Model

// Keep the Process object alive for SIGTERM cleanup after the last panel
// closes; Quickshell force-kills a Process destroyed with its QML owner.
// The helper itself exists only while a panel is open and Bluetooth is on.
// PINs and passkeys stay on the private process pipe; never log a message.
Singleton {
  id: root
  property int users: 0
  readonly property var adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property bool active: users > 0 && adapter !== null && adapter.enabled
  property bool ready: false
  property bool busy: false
  property var request: null
  property string deviceName: ""
  property string devicePath: ""
  property string message: ""

  function acquire() { root.users++ }
  function release() { root.users = Math.max(0, root.users - 1) }

  function send(doc) {
    if (!process.running)
      return false
    process.write(JSON.stringify(doc) + "\n")
    return true
  }

  function pair(path, name) {
    if (!root.ready || root.busy)
      return false
    root.deviceName = name
    root.devicePath = path
    root.message = "Pairing with " + name + "…"
    root.busy = true
    return root.send({ action: "pair", device: path })
  }

  function respond(accept, value) {
    if (root.request)
      root.send({ action: "respond", id: root.request.id, accept: accept, value: value || "" })
  }

  function cancel() {
    root.send({ action: "cancel" })
    root.request = null
    root.message = "Canceling pairing…"
  }

  function event(line) {
    const doc = Model.pairingEvent(line)
    if (!doc) {
      root.message = "The pairing response was not valid. Reopen the panel to retry."
      return
    }
    switch (doc.event) {
    case "ready": root.ready = true; root.message = ""; break
    case "pairing": root.busy = true; break
    case "prompt": root.request = doc; break
    case "clear": root.request = null; break
    case "error": root.message = doc.message; break
    case "result":
      root.busy = false
      root.devicePath = ""
      root.request = null
      root.message = doc.message
      break
    }
  }

  Process {
    id: process
    command: ["/usr/lib/subcult/bluetooth-pair-agent"]
    running: root.active
    stdinEnabled: true
    stdout: SplitParser { onRead: (line) => root.event(line) }
    onExited: {
      root.ready = false
      root.busy = false
      root.request = null
      root.devicePath = ""
      if (root.active)
        root.message = "Pairing stopped. Reopen the panel to retry."
      else
        root.message = ""
    }
  }
}
