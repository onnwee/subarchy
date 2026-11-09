pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../widgets/dell-power/Model.js" as Model

// Dell firmware power and charging profiles (ADR 0021), shared by the bar
// widget and its panel. The state comes from `subcult dell power state
// --json` when the widget appears, when the panel opens and after a local
// or daemon profile change; nothing polls. Changes go through `subcult dell power set` and
// `charging set`, which write the firmware files the udev rule handed to
// wheel. The IPC handler is for the tests.
Singleton {
  id: root

  property var report: null
  property bool busy: false
  property string error: ""
  property int users: 0 // widgets in a bar; the state is read while one is
  property bool refreshPending: false

  function refresh() {
    if (query.running)
      root.refreshPending = true
    else
      query.running = true
  }

  Connections {
    target: PowerProfiles
    function onProfileChanged() { root.refresh() }
  }

  function setProfile(id) {
    run(["subcult", "dell", "power", "set", String(id)])
  }

  function setCharging(id, start, stop) {
    const cmd = ["subcult", "dell", "power", "charging", "set", String(id)]
    if (id === "custom" && start !== undefined && stop !== undefined)
      cmd.push(String(start), String(stop))
    run(cmd)
  }

  function run(cmd) {
    if (change.running)
      return false
    root.error = ""
    root.busy = true
    change.command = cmd
    change.running = true
    return true
  }

  Process {
    id: query
    command: ["subcult", "dell", "power", "state", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        const r = Model.parse(text)
        if (r)
          root.report = r
      }
    }
    onExited: {
      if (root.refreshPending) {
        root.refreshPending = false
        root.refresh()
      }
    }
  }

  Process {
    id: change
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "")
          root.error = text.trim().replace(/^subcult dell power: /, "")
      }
    }
    onExited: (code) => {
      root.busy = false
      if (code !== 0 && root.error === "")
        root.error = "The change failed (exit " + code + ")."
      root.refresh()
    }
  }

  IpcHandler {
    target: "subcult.dell-power"
    function state(): string {
      return JSON.stringify({ report: root.report, busy: root.busy, error: root.error })
    }
    function setProfile(id: string): bool {
      root.setProfile(id)
      return true
    }
    function setCharging(id: string, start: string, stop: string): bool {
      if (start === "")
        root.setCharging(id)
      else
        root.setCharging(id, start, stop)
      return true
    }
  }
}
