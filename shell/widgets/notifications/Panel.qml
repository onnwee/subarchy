pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "../../Commons/Glyphs.js" as Glyphs

// The notification centre: the history newest first, each record with a
// close mark, a clear-all mark and the do-not-disturb switch in the header.
// It reads the service's history, which the daemon keeps; nothing polls.
PanelBase {
  id: panel

  readonly property var history: Notifications.history
  implicitWidth: 360
  implicitHeight: column.implicitHeight

  function when(ms) {
    const d = new Date(ms)
    const now = new Date()
    const same = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()
    return Qt.formatDateTime(d, same ? "h:mm AP" : "ddd d MMM h:mm AP")
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Item {
      width: parent.width
      height: 24
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Notifications"
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize + 1
        font.bold: true
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        IconButton {
          glyph: Glyphs.bell(0, Notifications.dnd)
          color: Notifications.dnd ? Theme.warning : Theme.subtext
          tooltip: Notifications.dnd ? "Do not disturb is on (click to turn off)" : "Do not disturb (click to turn on)"
          onClicked: Notifications.dnd = !Notifications.dnd
        }
        IconButton {
          glyph: Glyphs.clearAll
          color: panel.history.length > 0 ? Theme.subtext : Theme.muted
          tooltip: "Clear all"
          onClicked: Notifications.clearHistory()
        }
      }
    }

    Text {
      visible: panel.history.length === 0
      width: parent.width
      text: Notifications.dnd ? "No notifications. Do not disturb is on." : "No notifications"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Repeater {
      model: panel.history.slice(0, 30)
      delegate: Rectangle {
        id: card
        required property var modelData
        width: column.width
        height: body.implicitHeight + 2 * 6
        color: Theme.base
        border.width: 1
        border.color: card.modelData.urgency === "critical" ? Theme.error : Theme.surface

        Column {
          id: body
          x: 8
          y: 6
          width: parent.width - 8 - 28
          spacing: 2
          Text {
            width: parent.width
            text: card.modelData.summary || "(no summary)"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
            font.bold: true
          }
          Text {
            visible: text !== ""
            width: parent.width
            text: card.modelData.body || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
          Text {
            width: parent.width
            text: [card.modelData.appName, panel.when(card.modelData.time)].filter(s => s).join(" · ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.muted
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 2
          }
        }
        IconButton {
          anchors.right: parent.right
          anchors.rightMargin: 4
          anchors.top: parent.top
          anchors.topMargin: 4
          glyph: Glyphs.close
          color: Theme.muted
          tooltip: "Remove"
          onClicked: Notifications.removeRecord(card.modelData.id)
        }
      }
    }

    Text {
      visible: panel.history.length > 30
      width: parent.width
      text: (panel.history.length - 30) + " older"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }
  }
}
