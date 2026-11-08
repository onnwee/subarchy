pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "AlertsModel.js" as Model

// Battery alerts: low (20 %) and critical (10 %) once per crossing while
// on battery, with hysteresis (AlertsModel). Driven by UPower's property
// changes; nothing polls. Sent as notifications through notify-send, so
// they reach the shell's own daemon like any other.
Singleton {
  id: root

  readonly property var device: UPower.displayDevice
  property var state: Model.initial()

  function reading() {
    const d = root.device
    const raw = d ? Number(d.percentage) : NaN
    return { percent: isFinite(raw) ? Math.round(raw <= 1 ? raw * 100 : raw) : NaN, onBattery: UPower.onBattery }
  }

  function check() {
    if (!root.device || !root.device.isPresent)
      return
    const r = root.reading()
    const out = Model.step(root.state, r)
    root.state = out.state
    for (const a of out.alerts)
      root.notify(a, r.percent)
  }

  function notify(alert, percent) {
    const m = Model.message(alert, percent)
    Quickshell.execDetached(["notify-send", "-a", "Subarchy", "-u", m[0], "-i", "battery-caution", "--", m[1], m[2]])
  }

  Connections {
    target: root.device
    function onPercentageChanged() { root.check() }
    function onStateChanged() { root.check() }
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() { root.check() }
  }
}
