pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Keep the session awake (no idle lock, no display off). One state for the
// whole shell; the indicators toggle it. While on, a logind idle inhibitor
// is held through systemd-inhibit, which hypridle honours whatever window
// is in front (a Wayland idle inhibitor on the bar went inactive under a
// fullscreen window). The state lives in a file, so a shell restart keeps
// it; the file is watched, so writing "1" to it or removing it works too.
Singleton {
  id: root

  property bool enabled: false
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/keep-awake"

  onEnabledChanged: {
    if (!stateFile.settled)
      return
    if (root.enabled && stateFile.text.trim() !== "1")
      stateFile.setText("1\n")
    else if (!root.enabled && stateFile.exists)
      remove.running = true
  }

  Process {
    id: inhibit
    running: root.enabled
    command: ["systemd-inhibit", "--what=idle", "--who=SUBCULT", "--why=Keep awake", "--mode=block", "sleep", "infinity"]
  }

  Process {
    id: remove
    command: ["rm", "-f", root.statePath]
  }

  WatchedFile {
    id: stateFile
    path: root.statePath
    onChanged: root.enabled = stateFile.exists && stateFile.text.trim() === "1"
  }
}
