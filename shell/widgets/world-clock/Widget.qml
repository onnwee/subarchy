import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Other time zones, set in the bar config as "zones": ["Asia/Tokyo", ...].
// Offsets come from `date` at start and again at the top of each hour (for
// daylight saving), riding the shared minute clock; no timer of its own.
BarWidget {
  id: root

  readonly property var zones: Array.isArray(settings.zones) ? settings.zones : []
  property var offsets: ({})

  hidden: zones.length === 0
  implicitWidth: label.implicitWidth

  function refresh() {
    if (zones.length > 0)
      query.running = true
  }

  onZonesChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: Clock
    function onNowChanged() {
      if (Clock.now.getMinutes() === 0)
        root.refresh()
    }
  }

  Process {
    id: query
    // One line per zone, empty for a zone the system does not have (date
    // would print UTC for it), so the lines stay in the zones' order.
    command: ["sh", "-c", "for z do if [ -f \"/usr/share/zoneinfo/$z\" ]; then TZ=\"$z\" date +%z; else echo; fi; done", "sh"].concat(root.zones)
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n")
        const next = {}
        root.zones.forEach((z, i) => {
          const o = Model.parseOffset(lines[i] || "")
          if (o !== null)
            next[z] = o
        })
        root.offsets = next
      }
    }
  }

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    text: root.zones.filter(z => root.offsets[z] !== undefined)
      .map(z => Model.formatAt(Clock.now.getTime(), root.offsets[z], Model.label(z))).join("  ")
    color: Theme.subtext
    font.family: Style.fontFamily
    font.pixelSize: Style.fontSize
  }
}
