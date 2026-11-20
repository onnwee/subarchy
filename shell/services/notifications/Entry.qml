import QtQuick

// One popup's timer, owned by Notifications.qml. Only QtQuick, so the
// model tests can load it without Quickshell.
QtObject {
  id: entry
  required property var n
  property real due: 0 // epoch ms when it expires; 0 while it stays
  property int remaining: 0 // ms left while paused
  // The pointer is on the card. A replacement while held sets the new
  // timeout but waits for resume() to start it.
  property bool held: false

  signal expired(var n)

  readonly property Timer timer: Timer {
    repeat: false
    onTriggered: entry.expired(entry.n)
  }

  function arm(ms) {
    if (ms <= 0) {
      entry.timer.stop()
      entry.due = 0
      return
    }
    entry.due = Date.now() + ms
    if (entry.held) {
      entry.remaining = ms
      return
    }
    entry.timer.interval = ms
    entry.timer.restart()
  }

  function pause() {
    entry.held = true
    if (entry.due > 0 && entry.timer.running) {
      entry.remaining = Math.max(1000, entry.due - Date.now())
      entry.timer.stop()
    }
  }

  function resume() {
    entry.held = false
    if (entry.due > 0 && !entry.timer.running)
      entry.arm(entry.remaining)
  }
}
