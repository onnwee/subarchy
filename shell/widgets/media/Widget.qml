import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// The active media player's state and title. Click plays or pauses, a
// middle click opens the panel (all players, controls, local artwork),
// scroll goes to the next or previous track. MPRIS pushes changes;
// nothing polls. Hidden while no player is open.
BarWidget {
  id: root

  property string chosenId: ""
  readonly property var players: Mpris.players ? Mpris.players.values : [] // qmllint disable missing-property
  readonly property var player: Model.pick(players.map(p => ({ id: p.dbusName, playing: p.isPlaying, identity: p.identity, p: p })), chosenId)
  readonly property var active: player ? player.p : null

  hidden: active === null
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.active && root.active.isPlaying ? Glyphs.mediaPause : Glyphs.mediaPlay
    label: root.active ? Model.label(root.active.trackTitle, root.active.trackArtist, root.active.identity, 32) : ""
    color: root.active && root.active.isPlaying ? Theme.text : Theme.subtext
    tooltip: root.active ? root.active.identity : ""
    onClicked: (mouse) => {
      if (!root.active)
        return
      if (mouse.button === Qt.MiddleButton)
        root.openPanel()
      else if (root.active.canTogglePlaying)
        root.active.togglePlaying()
    }
    onScrolled: (delta) => {
      if (!root.active)
        return
      if (delta > 0 && root.active.canGoPrevious)
        root.active.previous()
      else if (delta < 0 && root.active.canGoNext)
        root.active.next()
    }
  }
}
