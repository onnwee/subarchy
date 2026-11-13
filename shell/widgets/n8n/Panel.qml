pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The server field, then the failed executions and the workflows from one
// check made when the panel opens. The key stays in the keyring: the panel
// shows the secret-tool command that stores it.
PanelBase {
  id: panel

  readonly property string server: Model.serverUrl(settings)
  property var report: null
  property int error: 0
  property bool checking: false
  // The server changed while a check was running: its result is stale.
  property bool recheck: false

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  function check() {
    if (panel.server === "" || query.running)
      return
    panel.checking = true
    query.command = Model.fetchCommand(panel.server)
    query.running = true
  }

  Component.onCompleted: check()
  // A server typed in the field is checked at once, as the bar widget does;
  // a check still running for the old server is redone when it ends.
  onServerChanged: {
    panel.report = null
    panel.error = 0
    if (query.running)
      panel.recheck = true
    else
      panel.check()
  }

  Process {
    id: query
    stdout: StdioCollector {
      onStreamFinished: {
        if (!panel.recheck)
          panel.report = Model.parse(text)
      }
    }
    onExited: (code) => {
      panel.checking = false
      if (panel.recheck) {
        panel.recheck = false
        panel.report = null
        panel.error = 0
        panel.check()
        return
      }
      panel.error = code
    }
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Text {
      text: "n8n"
      color: Theme.text
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
      font.bold: true
    }

    Rectangle {
      width: parent.width
      height: 24
      radius: 3
      color: Theme.surface
      TextInput {
        id: field
        anchors.fill: parent
        anchors.margins: 4
        verticalAlignment: TextInput.AlignVCenter
        text: String(panel.settings.server || "")
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
        focus: true
        onAccepted: {
          if (panel.shell.config)
            panel.shell.config.set("server", text.trim())
        }
        Text {
          visible: field.text === ""
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: "Server URL, then Enter (https://n8n.example.net)"
          color: Theme.muted
          font: field.font
        }
      }
    }

    Text {
      visible: panel.server === "" || panel.error === 3 || panel.error === 5
      width: parent.width
      text: (panel.server === "" ? "Set the server above. " : panel.error === 5 ? "The server answered with an error (check the key and the URL). " : "") + "The API key lives in the keyring: run\n" + Model.storeHint()
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Text {
      visible: panel.server !== "" && panel.error !== 0 && panel.error !== 3 && panel.error !== 5
      width: parent.width
      text: Model.errorText(panel.error) + ": " + panel.server
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.warning
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Text {
      visible: panel.checking && panel.report === null
      text: "Checking…"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Text {
      visible: panel.report !== null
      text: panel.report && panel.report.failed.length > 0 ? "Failed runs" : "No failed runs"
      color: panel.report && panel.report.failed.length > 0 ? Theme.error : Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
      font.bold: true
    }
    Repeater {
      model: panel.report ? panel.report.failed : []
      delegate: Text {
        id: run
        required property var modelData
        width: column.width
        text: Model.workflowName(panel.report, run.modelData.workflowId) + " · " + Model.ago(run.modelData.stoppedAt || run.modelData.startedAt, Clock.now)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
      }
    }

    Text {
      visible: panel.report !== null
      text: "Workflows"
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
      font.bold: true
    }
    ListView {
      width: parent.width
      height: Math.min(300, contentHeight)
      clip: true
      model: panel.report ? panel.report.workflows : []
      delegate: Row {
        id: wf
        required property var modelData
        width: ListView.view.width
        height: 22
        spacing: 6
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 7
          height: 7
          radius: 4
          color: wf.modelData.active ? Theme.accent : Theme.muted
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 13
          text: wf.modelData.name + (wf.modelData.active ? "" : " (off)")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: wf.modelData.active ? Theme.text : Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
      }
    }
  }
}
