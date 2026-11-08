import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// The coding agents' usage (ADR 0047; stage 3, off by default: add
// "subcult.agents" to the bar layout). Runs `subcult agent usage --json`,
// which reads Claude Code's and Codex's local files, on its timer and only
// while the widget is in the bar; nothing on the network. The bar shows each
// agent's tightest limit, or its tokens today when it keeps no limits on
// disk. Hidden until an agent has files. A click opens the panel.
BarWidget {
  id: root

  property var report: null
  readonly property var agents: Model.shown(report, settings.agents)
  readonly property string label: Model.barLabel(agents)

  hidden: agents.length === 0
  implicitWidth: button.implicitWidth

  function refresh() {
    if (!query.running)
      query.running = true
  }

  Component.onCompleted: refresh()

  WidgetTimer {
    widget: root
    timerName: "refresh"
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: query
    command: ["subcult", "agent", "usage", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        const r = Model.parse(text)
        if (r)
          root.report = r
      }
    }
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.agents
    label: root.mode === "full" ? root.label : ""
    color: Theme.subtext
    tooltip: Model.tooltip(root.agents)
    onClicked: root.openPanel()
  }
}
