import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Small status marks: keep-awake (click to toggle) and screen capture in
// progress. Both are driven by events. Only the PipeWire nodes that could
// be a video stream are tracked (see Model.js), not every stream.
BarWidget {
  id: root

  readonly property var candidates: Pipewire.nodes ? Pipewire.nodes.values.filter(n => Model.candidate({ type: n.type, name: n.name })) : [] // qmllint disable missing-property
  readonly property bool recording: Model.recording(candidates.map(n => ({
    mediaClass: n.properties ? n.properties["media.class"] : ""
  })))

  implicitWidth: row.implicitWidth

  PwObjectTracker {
    objects: root.candidates
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
