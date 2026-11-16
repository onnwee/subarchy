pragma Singleton
import QtQuick
import Quickshell

// Which widget's click-out panel is open: one at a time, for the whole
// shell. A WidgetHost toggles its own; PanelOverlay shows it on the host's
// output, centred in the available screen space.
Singleton {
  id: root

  property var host: null

  // Switching from one widget's panel to another's goes through closed, so
  // the overlay's loader drops the old Panel.qml and loads the new one.
  function toggle(h) {
    if (root.host === h) {
      root.close()
      return
    }
    root.host = null
    root.host = h
  }

  function close() {
    root.host = null
  }
}
