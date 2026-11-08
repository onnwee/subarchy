import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// The next event from the sync cache (ADR 0061): "Standup 14:00", "Standup
// now", "Tomorrow Dentist 09:00". The cache file is watched, so a sync
// updates the bar without polling; the label follows the shared minute
// clock. A click opens the month panel.
BarWidget {
  id: root

  readonly property string cachePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/calendar/events.json"
  readonly property var events: Model.events(cache.text)
  readonly property var nextEvent: Model.next(events, Clock.now)
  readonly property string label: Model.label(nextEvent, Clock.now)

  implicitWidth: row.implicitWidth

  WatchedFile {
    id: cache
    path: root.cachePath
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    IconButton {
      glyph: Glyphs.calendar
      color: root.nextEvent ? Theme.text : Theme.subtext
      tooltip: cache.exists ? (root.nextEvent ? root.label : "No upcoming events") : "No calendar sync yet (subcult calendar sync)"
      onClicked: root.openPanel()
    }
    Text {
      visible: root.mode === "full" && root.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      textFormat: Text.PlainText
      color: Theme.text
      font.family: Style.fontFamily
      font.pixelSize: Style.fontSize

      MouseArea {
        anchors.fill: parent
        onClicked: root.openPanel()
      }
    }
  }
}
