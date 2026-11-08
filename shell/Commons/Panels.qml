pragma Singleton
import QtQuick
import Quickshell

// Which widget's click-out panel is open: one at a time, for the whole
// shell. A WidgetHost toggles its own; PanelOverlay shows it on the host's
// output, under the host's place in the bar.
Singleton {
  id: root

  property var host: null
  property real anchorX: 0

  function toggle(h) {
    if (root.host === h) {
      root.close()
      return
    }
    root.anchorX = h.mapToItem(null, 0, 0).x
    root.host = h
  }

  function close() {
    root.host = null
  }
}
