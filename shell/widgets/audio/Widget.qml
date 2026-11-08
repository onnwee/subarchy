import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// The default output's volume. Scroll changes it by 5 %, a middle click
// mutes, a click opens the audio panel (devices, volumes, mute). PipeWire
// pushes changes; nothing polls.
BarWidget {
  id: root

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink && sink.audio ? sink.audio : null

  hidden: audio === null
  implicitWidth: button.implicitWidth

  PwObjectTracker {
    objects: root.sink ? [root.sink] : []
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.audio ? Glyphs.volume(root.audio.volume, root.audio.muted) : ""
    color: Theme.subtext
    tooltip: root.audio ? (root.sink.description || root.sink.name) + " " + Math.round(root.audio.volume * 100) + "%" : ""
    onClicked: (mouse) => {
      if (mouse.button === Qt.MiddleButton && root.audio)
        root.audio.muted = !root.audio.muted
      else
        root.openPanel()
    }
    onScrolled: (delta) => {
      if (root.audio)
        root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + (delta > 0 ? 0.05 : -0.05)))
    }
  }
}
