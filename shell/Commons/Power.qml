pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "PowerModel.js" as PowerModel

// On-battery state and timer intervals (ADR 0054, ADR 0068). Widgets ask
// for an interval by timer name; it changes the moment the power source
// changes. A machine without a battery is always on AC.
Singleton {
  id: root

  readonly property bool onBattery: UPower.onBattery

  function interval(manifest, timerName) {
    return PowerModel.intervalMs(manifest, timerName, root.onBattery)
  }
}
