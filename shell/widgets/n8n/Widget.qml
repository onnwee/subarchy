import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// n8n in the bar (shell plan 2): active workflows over all, and the count
// of recent failed executions. Hidden until a server is set; the key comes
// from the keyring through secret-tool at every check and is never stored
// in the config or put on a command line. Checked on the manifest timer: a
// minute on AC, five on battery.
BarWidget {
  id: root

  readonly property string server: Model.serverUrl(settings)
  property var report: null
  property int error: 0
  readonly property string label: Model.label(report)

  hidden: server === ""
  implicitWidth: button.implicitWidth

  function refresh() {
    if (root.server !== "" && !query.running) {
      query.command = Model.fetchCommand(root.server)
      query.running = true
    }
  }

  onServerChanged: {
    root.report = null
    root.error = 0
    root.refresh()
  }
  // A settings change (the server, or a key stored and the panel used) is
  // the moment to check again.
  onSettingsChanged: root.refresh()
  Component.onCompleted: refresh()

  WidgetTimer {
    widget: root
    timerName: "refresh"
    running: root.server !== ""
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: query
    stdout: StdioCollector {
      onStreamFinished: {
        const d = Model.parse(text)
        if (d)
          root.report = d
      }
    }
    onExited: (code) => {
      root.error = code
      if (code !== 0 && code !== 4)
        root.report = null
    }
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.n8n
    label: root.mode === "full" ? (root.report ? root.label : (root.error !== 0 ? "!" : "")) : ""
    color: root.error !== 0 ? Theme.warning : (root.report && root.report.failed.length > 0 ? Theme.error : Theme.subtext)
    tooltip: root.error !== 0 ? "n8n: " + Model.errorText(root.error)
      : (root.report ? "n8n: " + root.report.workflows.filter(w => w.active).length + " active workflows, " + root.report.failed.length + " failed runs" : "n8n")
    onClicked: root.openPanel()
  }
}
