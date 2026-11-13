pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "AlertsModel.js" as Model

// Battery alerts: low (20 %) and critical (10 %) once per crossing while
// on battery, with hysteresis (AlertsModel). Driven by UPower's property
// changes; nothing polls. Thermal alerts: a hot or critical trip point
// crossed, from the kernel's events through `subcult thermal watch`, a
// process that sleeps on a netlink socket and prints a line per crossing;
// once per excursion with a cooldown per zone. Both are sent as
// notifications through notify-send, so they reach the shell's own daemon
// like any other.
Singleton {
  id: root

  readonly property var device: UPower.displayDevice
  property var state: Model.initial()
  property var thermal: Model.thermalInitial()

  function thermalLine(line) {
    const e = Model.parseThermal(line)
    if (!e)
      return
    const out = Model.thermalStep(root.thermal, e, Date.now())
    root.thermal = out.state
    if (out.alert) {
      const m = Model.thermalMessage(e)
      Quickshell.execDetached(["notify-send", "-a", "Subarchy", "-u", m[0], "-i", "temperature-warning", "--", m[1], m[2]])
    }
  }

  Process {
    id: thermalWatch
    property double startedAt: 0
    command: ["subcult", "thermal", "watch"]
    running: true
    stdout: SplitParser {
      onRead: (line) => root.thermalLine(line)
    }
    onRunningChanged: {
      if (running)
        startedAt = Date.now()
    }
    // Exit 3: a kernel without thermal netlink events. The watch is not
    // restarted: the alert source is gone until the next shell start. Any
    // other exit starts it again after a delay that doubles up to the cap,
    // and goes back to the first delay after a run longer than the cap.
    onExited: (code) => {
      if (code === 3)
        return
      console.warn("subcult shell: thermal watch ended with", code)
      if (Date.now() - startedAt > thermalRetry.cap)
        thermalRetry.interval = thermalRetry.first
      thermalRetry.start()
    }
  }

  Timer {
    id: thermalRetry
    readonly property int first: 30000
    readonly property int cap: 600000
    interval: first
    onTriggered: {
      thermalWatch.running = true
      interval = Math.min(interval * 2, cap)
    }
  }

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
