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

  Component.onCompleted: Tailscale.refresh()

  WidgetTimer {
    widget: root
    timerName: "refresh"
    running: true
    repeat: true
    onTriggered: Tailscale.refresh()
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
