pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "PowerModel.js" as PowerModel

// On-battery state and timer intervals (ADR 0054, ADR 0068). Widgets ask
// for an interval by timer name; it changes the moment the power source
// changes. A machine without a battery is always on AC. Widget timers
// register here so the shell can report what actually runs.
Singleton {
  id: root

  readonly property bool onBattery: UPower.onBattery
  property var timers: []

  function interval(manifest, timerName) {
    return PowerModel.intervalMs(manifest, timerName, root.onBattery)
  }

  function register(timer) {
    root.timers = root.timers.concat([timer])
  }

  function unregister(timer) {
    root.timers = root.timers.filter(t => t !== timer)
  }

  // { "<widget id>.<timer name>": { interval, running } }
  function report() {
    const out = {}
    for (const t of root.timers)
      out[t.widgetId + "." + t.timerName] = { interval: t.interval, running: t.running }
    return out
  }
}
