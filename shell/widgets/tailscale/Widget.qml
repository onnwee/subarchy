import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Tailscale in the bar (ADR 0058): connected or not, with this machine's
// name and address and the machines online in the tooltip. Reads
// `tailscale status --json` on the manifest timer (a minute on AC, five on
// battery); the panel and its actions read it again at once. Hidden when
// the tailscale package is not installed. A click opens the panel.
BarWidget {
  id: root

  readonly property var status: Tailscale.status
  readonly property bool running: status !== null && status.running

  hidden: !Tailscale.installed
  implicitWidth: button.implicitWidth

  Component.onCompleted: Tailscale.readStatus()

  WidgetTimer {
    id: refreshTimer
    widget: root
    timerName: "refresh"
    running: false
    repeat: true
    onTriggered: Tailscale.readStatus()
  }

  // Share the clock's minute boundary, so a status refresh and clock
  // redraw can use the same wake-up. Re-align after a power-source change.
  Connections {
    target: Clock
    enabled: !refreshTimer.running
    function onNowChanged() {
      Tailscale.readStatus()
      refreshTimer.start()
    }
  }

  Connections {
    target: Power
    function onOnBatteryChanged() { refreshTimer.stop() }
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.tailscale(root.running)
    color: root.running ? Theme.subtext : Theme.muted
    tooltip: Model.tooltip(root.status, Tailscale.daemonDown)
    onClicked: root.openPanel()
  }
}
