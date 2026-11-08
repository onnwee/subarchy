pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A month with a mark on days that have events, and the selected day's
// events under it. Reads the same cache as the widget; exists only while
// open.
PanelBase {
  id: panel

  readonly property string cachePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/calendar/events.json"
  readonly property var events: Model.events(cache.text)
  readonly property var synced: Model.syncedAt(cache.text)
  property date month: new Date(Clock.now.getFullYear(), Clock.now.getMonth(), 1)
  property date selected: Model.startOfDay(Clock.now)
  readonly property var cells: Model.grid(month, Clock.now, events, 1)
  readonly property var dayEvents: Model.onDay(events, selected)
  readonly property int cell: 36

  implicitWidth: 7 * cell
  implicitHeight: column.implicitHeight

  WatchedFile {
    id: cache
    path: panel.cachePath
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Item {
      width: parent.width
      height: 24
      IconButton {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\u{F0141}" // chevron_left
        color: Theme.subtext
        tooltip: "Previous month"
        onClicked: panel.month = Model.shiftMonth(panel.month, -1)
      }
      Text {
        anchors.centerIn: parent
        text: Qt.formatDate(panel.month, "MMMM yyyy")
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize + 1
        font.bold: true
        MouseArea {
          anchors.fill: parent
          onClicked: {
            panel.month = new Date(Clock.now.getFullYear(), Clock.now.getMonth(), 1)
            panel.selected = Model.startOfDay(Clock.now)
          }
        }
      }
      IconButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\u{F0142}" // chevron_right
        color: Theme.subtext
        tooltip: "Next month"
        onClicked: panel.month = Model.shiftMonth(panel.month, 1)
      }
    }

    Grid {
      columns: 7
      Repeater {
        model: Model.weekdays(1)
        delegate: Text {
          required property string modelData
          width: panel.cell
          horizontalAlignment: Text.AlignHCenter
          text: modelData
          color: Theme.muted
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
      }
    }

    Grid {
      columns: 7
      Repeater {
        model: panel.cells
        delegate: Rectangle {
          id: day
          required property var modelData
          readonly property bool isSelected: Model.sameDay(modelData.date, panel.selected)
          width: panel.cell
          height: panel.cell - 4
          radius: 3
          color: isSelected ? Theme.selection : "transparent"
          border.width: modelData.today ? 1 : 0
          border.color: Theme.accent

          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -2
            text: day.modelData.date.getDate()
            color: day.modelData.inMonth ? Theme.text : Theme.muted
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Rectangle {
            visible: day.modelData.count > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            width: 4
            height: 4
            radius: 2
            color: Theme.accent
          }
          MouseArea {
            anchors.fill: parent
            onClicked: panel.selected = day.modelData.date
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Theme.surface
    }

    Text {
      width: parent.width
      text: Qt.formatDate(panel.selected, "dddd d MMMM")
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
      font.bold: true
    }
    Text {
      visible: panel.dayEvents.length === 0
      width: parent.width
      text: cache.exists ? "No events" : "No calendar sync yet: configure ~/.config/subcult/calendar.toml and run subcult calendar sync"
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
    Repeater {
      model: panel.dayEvents
      delegate: Column {
        id: ev
        required property var modelData
        width: column.width
        Text {
          width: parent.width
          text: Model.line(ev.modelData)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        Text {
          visible: text !== ""
          width: parent.width
          text: [ev.modelData.location, ev.modelData.calendar].filter(s => s !== "").join(" · ")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
      }
    }
    Text {
      visible: panel.synced !== null
      width: parent.width
      text: panel.synced ? "Synced " + Qt.formatDateTime(panel.synced, "ddd d MMM h:mm AP") : ""
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }
  }
}
