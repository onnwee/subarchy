pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The commands the settings panel's Apply and Undo run (`subcult font set`,
// `subcult cursor apply`, `subcult idle apply`), one after the other. The
// Process lives here, not in the panel, so closing the panel mid-command
// neither kills the running one nor drops the queued ones; Quickshell
// force-kills a Process destroyed with its owner.
Singleton {
  id: root

  property var queue: []
  // The last failure since the queue was last empty, else "".
  property string status: ""

  // Emitted when the queue has run dry.
  signal finished()

  function run(commands) {
    if (!commands || commands.length === 0)
      return
    if (!runner.running && root.queue.length === 0)
      root.status = ""
    root.queue = root.queue.concat(commands)
    if (!runner.running)
      root.next()
  }

  function next() {
    if (root.queue.length === 0) {
      root.finished()
      return
    }
    runner.command = root.queue[0]
    root.queue = root.queue.slice(1)
    runner.running = true
  }

  Process {
    id: runner
    onExited: (code) => {
      if (code !== 0)
        root.status = "A command failed (exit " + code + "): " + runner.command.join(" ")
      root.next()
    }
  }
}
