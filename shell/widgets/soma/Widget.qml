import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// SomaFM in the bar (shell plan 2): the channel and the song while playing,
// a radio glyph while not. Playback lives in the Soma service, driven by
// mpv's events; the widget itself has no timer. Click opens the panel;
// middle click stops or resumes.
BarWidget {
  id: root

  readonly property bool playing: Soma.playing
  readonly property string nowPlaying: Soma.song
  readonly property string label: Model.label(Soma.channel, Soma.song)

  implicitWidth: button.implicitWidth

  onSettingsChanged: Soma.format = String(settings.format || "aac")
  Component.onCompleted: Soma.format = String(settings.format || "aac")

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.radio
    label: root.playing && root.mode === "full" ? root.label : ""
    color: Soma.playError !== "" ? Theme.warning : (root.playing ? Theme.text : Theme.subtext)
    tooltip: Soma.playError !== "" ? "SomaFM: " + Soma.playError
      : (root.playing ? root.label : (Soma.channel ? "SomaFM: " + Soma.channel.title + " (stopped)" : "SomaFM"))
    onClicked: (m) => {
      if (m.button === Qt.MiddleButton)
        Soma.toggle()
      else
        root.openPanel()
    }
  }
}
