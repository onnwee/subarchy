pragma Singleton
import QtQuick
import Quickshell

// The one clock in the shell: it wakes once a minute, aligned to the
// minute (ADR 0054). Every widget that shows time binds to `now`.
Singleton {
  readonly property date now: clock.date

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}
