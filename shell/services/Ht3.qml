pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets/ht3/Model.js" as Model

// The HT3 panel's device helper, `subcult ht3 watch <address>`. It runs
// only while a panel holds it (acquire on open, release on close) and holds
// the headset's control channel; audio is untouched. The Process lives
// here, not in the panel, so closing the panel stops the helper with
// SIGTERM; Quickshell force-kills a Process destroyed with its owner.
Singleton {
  id: root
  property int users: 0
  property string address: ""
  readonly property bool active: users > 0 && address !== ""
  property bool connected: false
  property int battery: -1
  property string mode: ""
  property string message: ""

  function acquire(addr) {
    if (!root.active)
      root.address = addr
    root.users++
  }
  function release() {
    root.users = Math.max(0, root.users - 1)
  }

  function event(line) {
    const doc = Model.event(line)
    if (!doc) {
      root.message = "The headphones' helper sent something unexpected. Reopen the panel to retry."
      return
    }
    switch (doc.event) {
    case "connected": root.connected = true; root.message = ""; break
    case "state": root.battery = doc.battery; root.mode = doc.mode; break
    case "error": root.clear(); root.message = doc.message; break
    }
  }

  // No reading is current once the channel is gone, so none stays on screen.
  function clear() {
    root.connected = false
    root.battery = -1
    root.mode = ""
  }

  Process {
    id: process
    command: ["subcult", "ht3", "watch", root.address]
    running: root.active
    stdout: SplitParser { onRead: (line) => root.event(line) }
    onRunningChanged: {
      if (!running)
        return
      root.clear()
      root.message = ""
    }
    onExited: {
      root.clear()
      if (root.active && root.message === "")
        root.message = "The headphones' helper stopped. Reopen the panel to retry."
    }
  }
}
