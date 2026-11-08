import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Small status marks: do-not-disturb, the privacy marks (microphone, camera
// and screen in use, from PipeWire links and node flags) and keep-awake
// (click to toggle). All are driven by events. Only the PipeWire nodes that
// could be a video stream are tracked (see Model.js), not every stream.
BarWidget {
  id: root

  readonly property var candidates: Pipewire.nodes ? Pipewire.nodes.values.filter(n => Model.candidate({ type: n.type, name: n.name })) : [] // qmllint disable missing-property
  readonly property var captures: Model.captures(candidates.map(n => ({
    id: n.id,
    mediaClass: n.properties ? n.properties["media.class"] : ""
  })))
  readonly property var links: Pipewire.links ? Pipewire.links.values : [] // qmllint disable missing-property
  readonly property var marks: Model.marks(links.map(l => ({
    sourceType: l.source ? l.source.type : 0,
    targetId: l.target ? l.target.id : -1
  })), captures)

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
      visible: root.marks.microphone
      glyph: Glyphs.microphone(false)
      color: Theme.error
      tooltip: "Microphone in use"
    }

    IconButton {
      visible: root.marks.camera
      glyph: Glyphs.camera
      color: Theme.error
      tooltip: "Camera in use"
    }

    IconButton {
      visible: root.marks.screen
      glyph: Glyphs.screenShare
      color: Theme.error
      tooltip: "Screen shared or recorded"
    }

    IconButton {
      glyph: Glyphs.idleInhibit
      color: KeepAwake.enabled ? Theme.accent : Theme.muted
      tooltip: KeepAwake.enabled ? "Staying awake" : "Keep awake"
      onClicked: KeepAwake.enabled = !KeepAwake.enabled
    }
  }
}
