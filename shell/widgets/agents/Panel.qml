pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Per agent: tokens today and this week, the pace over the last hour, the
// sessions active today, and each rate limit with its reset. Runs the usage
// command once when it opens (the command's cache makes that cheap); exists
// only while open.
PanelBase {
  id: panel

  property var report: null
  readonly property var agents: Model.shown(report, settings.agents)
  readonly property var all: report ? report.agents : []

  implicitWidth: 320
  implicitHeight: column.implicitHeight

  Component.onCompleted: query.running = true

  Process {
    id: query
    command: ["subcult", "agent", "usage", "--json"]
    stdout: StdioCollector {
      onStreamFinished: panel.report = Model.parse(text)
    }
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 8

    Text {
      visible: panel.report === null
      text: query.running ? "Reading the agents' files…" : "subcult agent usage gave no answer"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Repeater {
      model: panel.all
      delegate: Column {
        id: agent
        required property var modelData
        readonly property var today: modelData.today || ({})
        readonly property var week: modelData.week || ({})
        width: column.width
        spacing: 3

        Row {
          width: parent.width
          Text {
            text: agent.modelData.name + (agent.modelData.plan ? " · " + agent.modelData.plan : "")
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
            font.bold: true
          }
        }
        Text {
          visible: !agent.modelData.found
          text: "Not set up on this machine"
          color: Theme.muted
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
        Text {
          visible: agent.modelData.found
          width: parent.width
          text: "Today " + Model.tokens(agent.today.total) + " (" + Model.tokens(agent.today.output) + " out) · week "
            + Model.tokens(agent.week.total) + " · " + Model.tokens(agent.modelData.paceHour) + "/h · "
            + agent.modelData.sessions + (agent.modelData.sessions === 1 ? " session" : " sessions")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
        Repeater {
          model: agent.modelData.found && Array.isArray(agent.modelData.limits) ? agent.modelData.limits : []
          delegate: Column {
            id: lim
            required property var modelData
            readonly property real used: Math.max(0, Math.min(100, Number(modelData.usedPercent) || 0))
            width: agent.width
            spacing: 2
            Text {
              width: parent.width
              text: Model.window(lim.modelData) + " window: " + Math.round(lim.used) + "%  " + Model.resets(lim.modelData, Clock.now)
              textFormat: Text.PlainText
              color: Theme.subtext
              font.family: Style.uiFontFamily
              font.pixelSize: Style.fontSize - 1
            }
            Rectangle {
              width: parent.width
              height: 4
              radius: 2
              color: Theme.surface
              Rectangle {
                width: parent.width * lim.used / 100
                height: parent.height
                radius: 2
                color: lim.used >= 90 ? Theme.error : Theme.accent
              }
            }
          }
        }
        Text {
          visible: agent.modelData.found && (!Array.isArray(agent.modelData.limits) || agent.modelData.limits.length === 0)
          text: "No limits on disk; the tool shows them itself"
          color: Theme.muted
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 2
        }
      }
    }

    Text {
      visible: panel.report !== null
      width: parent.width
      text: "Local files only · read " + (panel.report ? Qt.formatDateTime(new Date(panel.report.scannedAt), "hh:mm") : "")
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }
  }
}
