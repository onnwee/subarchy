pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model

// Paste a URL, press Enter or Download: it joins the queue. Each job shows
// its state; finished ones open their folder on click.
PanelBase {
  id: panel

  implicitWidth: 400
  implicitHeight: column.implicitHeight

  function submit() {
    const u = Model.url(field.text)
    if (u === "")
      return
    Downloads.add(u, panel.settings)
    field.text = ""
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: Style.spacing

    Rectangle {
      width: parent.width
      height: 32
      color: Theme.base
      border.width: 1
      border.color: field.activeFocus ? Theme.accent : Theme.surface

      TextInput {
        id: field
        anchors.fill: parent
        anchors.leftMargin: Style.spacing
        anchors.rightMargin: Style.spacing
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.selection
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize + 1
        focus: true
        onAccepted: panel.submit()
        Text {
          visible: field.text === ""
          anchors.verticalCenter: parent.verticalCenter
          text: "Paste a video or audio URL and press Enter"
          color: Theme.muted
          font: field.font
        }
      }
    }

    Row {
      spacing: Style.spacing
      Rectangle {
        width: download.implicitWidth + 2 * Style.padding
        height: download.implicitHeight + Style.padding
        color: Theme.base
        border.width: 1
        border.color: Theme.surface
        Text {
          id: download
          anchors.centerIn: parent
          text: panel.settings.audioOnly ? "Download audio" : "Download"
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        MouseArea {
          anchors.fill: parent
          onClicked: panel.submit()
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "to " + Model.expandHome(panel.settings.directory, Quickshell.env("HOME"))
        color: Theme.muted
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
      }
    }

    Text {
      visible: Downloads.jobs.length === 0
      text: "Nothing downloading"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Repeater {
      model: Downloads.jobs
      delegate: Item {
        id: row
        required property var modelData
        width: column.width
        height: 40

        Column {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: 3
          Text {
            width: parent.width
            text: Model.fileName(row.modelData.title || row.modelData.file || row.modelData.url)
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Text {
            width: parent.width
            text: row.modelData.status === "running"
              ? Math.round(row.modelData.percent) + "%" + (row.modelData.speed ? " · " + row.modelData.speed : "") + (row.modelData.eta ? " · " + row.modelData.eta : "")
              : row.modelData.status === "failed" ? "Failed: " + (row.modelData.error || "yt-dlp exited")
              : row.modelData.status === "done" ? "Done · click to open the folder" : "Queued"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.modelData.status === "failed" ? Theme.error : Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
          Rectangle {
            visible: row.modelData.status === "running"
            width: parent.width
            height: 3
            color: Theme.surface
            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, row.modelData.percent / 100))
              height: parent.height
              color: Theme.accent
            }
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (row.modelData.status === "done" && row.modelData.file)
              Quickshell.execDetached(["uwsm-app", "--", "xdg-open", row.modelData.file.slice(0, row.modelData.file.lastIndexOf("/"))])
            else if (row.modelData.status !== "running")
              Downloads.remove(row.modelData.id)
          }
        }
      }
    }
  }
}
