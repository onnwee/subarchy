pragma Singleton
import QtQuick
import Quickshell

// Keep the session awake (no idle lock, no display off). One state for the
// whole shell; shell.qml holds the idle inhibitor, the indicators toggle it.
Singleton {
  property bool enabled: false
}
