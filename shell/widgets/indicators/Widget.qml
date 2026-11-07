import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Small status marks: keep-awake (click to toggle) and screen capture in
// progress. Both are driven by events.
BarWidget {
  id: root

  readonly property var streams: Pipewire.nodes ? Pipewire.nodes.values.filter(n => n.isStream) : [] // qmllint disable missing-property
  readonly property bool recording: Model.recording(streams.map(n => ({
    isStream: n.isStream,
    mediaClass: n.properties ? n.properties["media.class"] : ""
  })))

  implicitWidth: row.implicitWidth

  PwObjectTracker {
    objects: root.streams
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    IconButton {
      visible: Notifications.dnd
      glyph: Glyphs.bell(0, true)
      color: Theme.warning
      tooltip: "Do not disturb (click to turn off)"
      onClicked: Notifications.dnd = false
    }

    IconButton {
      visible: root.recording
      glyph: Glyphs.recording
      color: Theme.error
      tooltip: "Screen capture in progress"
    }

    IconButton {
      glyph: Glyphs.idleInhibit
      color: KeepAwake.enabled ? Theme.accent : Theme.muted
      tooltip: KeepAwake.enabled ? "Staying awake" : "Keep awake"
      onClicked: KeepAwake.enabled = !KeepAwake.enabled
    }
  }
}
