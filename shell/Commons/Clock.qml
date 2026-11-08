pragma Singleton
import QtQuick
import Quickshell
import "ClockModel.js" as Model

// The one clock in the shell: it wakes once a minute, just after the
// minute changes (ADR 0054). Every widget that shows time binds to `now`.
// A single-shot timer re-armed from epoch time after each tick, rather than
// SystemClock, which re-arms at 1 ms through the repeated hour when
// daylight saving ends.
Singleton {
  id: root

  readonly property date now: new Date(root.nowMs)
  property real nowMs: Date.now()

  function tick() {
    root.nowMs = Date.now()
    tickTimer.interval = Model.nextDelayMs(root.nowMs)
    tickTimer.start()
  }

  Timer {
    id: tickTimer
    repeat: false
    onTriggered: root.tick()
  }

  Component.onCompleted: root.tick()
}
