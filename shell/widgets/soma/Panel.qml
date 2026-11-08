pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Now playing with a stop button, a filter box and the channel list from
// somafm.com, fetched when the panel opens (at most every ten minutes).
// Click a channel to play it.
PanelBase {
  id: panel

  property string query: ""
  readonly property var shown: Model.filter(Soma.channels, query)

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  Component.onCompleted: Soma.loadChannels()

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Row {
      width: parent.width
      spacing: 6
      IconButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: Soma.playing ? Glyphs.stop : Glyphs.play
        color: Soma.channel ? Theme.text : Theme.muted
        tooltip: Soma.playing ? "Stop" : "Play"
        onClicked: Soma.toggle()
      }
      Column {
        width: parent.width - 30
        Text {
          width: parent.width
          text: Soma.channel ? Soma.channel.title : "SomaFM"
          elide: Text.ElideRight
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
          font.bold: true
        }
        Text {
          width: parent.width
          text: Soma.playing ? (Soma.song !== "" ? Soma.song : "Tuning in…") : (Soma.channel ? "Stopped" : "Pick a channel")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 24
      radius: 3
      color: Theme.surface
      TextInput {
        id: filter
        anchors.fill: parent
        anchors.margins: 4
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
        focus: true
        onTextChanged: panel.query = text
        Text {
          visible: filter.text === ""
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: "Filter channels"
          color: Theme.muted
          font: filter.font
        }
      }
    }

    Text {
      visible: Soma.channels.length === 0
      width: parent.width
      text: Soma.channelsError !== "" ? Soma.channelsError : "Loading channels…"
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    ListView {
      width: parent.width
      height: Math.min(360, contentHeight)
      clip: true
      model: panel.shown
      delegate: Rectangle {
        id: row
        required property var modelData
        width: ListView.view.width
        height: 38
        radius: 3
        color: Soma.channelId === modelData.id ? Theme.selection : "transparent"
        Column {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: listeners.left
          anchors.leftMargin: 6
          Text {
            width: parent.width
            text: row.modelData.title
            elide: Text.ElideRight
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Text {
            width: parent.width
            text: row.modelData.genre + (row.modelData.description !== "" ? " · " + row.modelData.description : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 2
          }
        }
        Text {
          id: listeners
          anchors.right: parent.right
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.listeners > 0 ? String(row.modelData.listeners) : ""
          color: Theme.muted
          font.family: Style.fontFamily
          font.pixelSize: Style.fontSize - 2
        }
        MouseArea {
          anchors.fill: parent
          onClicked: Soma.play(row.modelData.id)
        }
      }
    }
  }
}
