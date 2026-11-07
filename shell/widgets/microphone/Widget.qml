import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// The default input. Click mutes; a muted microphone shows in the warning
// colour so it is easy to spot.
BarWidget {
  id: root

  readonly property var source: Pipewire.defaultAudioSource
  readonly property var audio: source && source.audio ? source.audio : null

  hidden: audio === null
  implicitWidth: button.implicitWidth

  PwObjectTracker {
    objects: root.source ? [root.source] : []
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.audio ? Glyphs.microphone(root.audio.muted) : ""
    color: root.audio && root.audio.muted ? Theme.warning : Theme.subtext
    tooltip: root.audio ? (root.source.description || root.source.name) + (root.audio.muted ? " (muted)" : "") : ""
    onClicked: if (root.audio) root.audio.muted = !root.audio.muted
  }
}
