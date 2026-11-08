pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Every open player: artwork (local files only), artist and title, and
// previous, play/pause and next. Click a player to make it the bar's.
PanelBase {
  id: panel

  property string chosenId: ""
  readonly property var players: Mpris.players ? Mpris.players.values : [] // qmllint disable missing-property
  readonly property var active: Model.pick(players.map(p => ({ id: p.dbusName, playing: p.isPlaying, identity: p.identity, p: p })), chosenId)

  implicitWidth: 360
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: panel.implicitWidth
    spacing: Style.spacing

    Text {
      visible: panel.players.length === 0
      text: "No media player is open"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Repeater {
      model: panel.players
      delegate: Rectangle {
        id: row
        required property var modelData
        readonly property bool isActive: panel.active !== null && panel.active.id === modelData.dbusName
        width: column.width
        height: 64
        color: isActive ? Theme.selection : "transparent"
        border.width: isActive ? 1 : 0
        border.color: Theme.accent

        MouseArea {
          anchors.fill: parent
          onClicked: panel.chosenId = row.modelData.dbusName
        }

        Image {
          id: art
          x: Style.spacing
          anchors.verticalCenter: parent.verticalCenter
          width: 48
          height: 48
          source: Model.artSource(row.modelData.trackArtUrl)
          visible: source !== ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
        }
        Text {
          visible: !art.visible
          x: Style.spacing
          anchors.verticalCenter: parent.verticalCenter
          width: 48
          horizontalAlignment: Text.AlignHCenter
          text: Glyphs.mediaNote
          color: Theme.muted
          font.family: Style.fontFamily
          font.pixelSize: Style.iconSize + 10
        }

        Column {
          anchors.left: parent.left
          anchors.leftMargin: 48 + 2 * Style.spacing
          anchors.right: controls.left
          anchors.rightMargin: Style.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            text: row.modelData.trackTitle || row.modelData.identity
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize + 1
          }
          Text {
            width: parent.width
            text: [row.modelData.trackArtist, row.modelData.identity].filter(s => s && s !== "").join(" · ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          IconButton {
            glyph: Glyphs.mediaPrevious
            color: row.modelData.canGoPrevious ? Theme.text : Theme.muted
            tooltip: "Previous"
            onClicked: if (row.modelData.canGoPrevious) row.modelData.previous()
          }
          IconButton {
            glyph: row.modelData.isPlaying ? Glyphs.mediaPause : Glyphs.mediaPlay
            color: row.modelData.canTogglePlaying ? Theme.text : Theme.muted
            tooltip: row.modelData.isPlaying ? "Pause" : "Play"
            onClicked: if (row.modelData.canTogglePlaying) row.modelData.togglePlaying()
          }
          IconButton {
            glyph: Glyphs.mediaNext
            color: row.modelData.canGoNext ? Theme.text : Theme.muted
            tooltip: "Next"
            onClicked: if (row.modelData.canGoNext) row.modelData.next()
          }
        }
      }
    }
  }
}
