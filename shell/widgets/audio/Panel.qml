pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Outputs and inputs with their volumes. Click a name to make it the
// default, the icon to mute, the bar to set the volume. The nodes are
// tracked only while the panel is open; PipeWire pushes changes.
PanelBase {
  id: panel

  readonly property var devices: Model.devices(Pipewire.nodes ? Pipewire.nodes.values : []) // qmllint disable missing-property
  readonly property var tracked: devices.sinks.concat(devices.sources)

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  PwObjectTracker {
    objects: panel.tracked
  }

  component Section: Column {
    id: section
    required property string title
    required property var nodes
    required property bool outputs
    width: panel.implicitWidth
    spacing: 4

    Text {
      text: section.title
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
      font.bold: true
    }
    Text {
      visible: section.nodes.length === 0
      text: "None"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
    Repeater {
      model: section.nodes
      delegate: Item {
        id: row
        required property var modelData
        readonly property var audio: modelData.audio
        readonly property bool isDefault: section.outputs ? Pipewire.defaultAudioSink === modelData : Pipewire.defaultAudioSource === modelData
        width: section.width
        height: 44

        IconButton {
          id: mute
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          glyph: row.audio ? (section.outputs ? Glyphs.volume(row.audio.volume, row.audio.muted) : Glyphs.microphone(row.audio.muted)) : ""
          color: row.audio && row.audio.muted ? Theme.muted : Theme.text
          tooltip: row.audio && row.audio.muted ? "Unmute" : "Mute"
          onClicked: if (row.audio) row.audio.muted = !row.audio.muted
        }
        Column {
          anchors.left: mute.right
          anchors.leftMargin: Style.spacing
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Text {
            width: parent.width
            text: (row.isDefault ? "● " : "") + (row.modelData.description || row.modelData.name)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.isDefault ? Theme.text : Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
            MouseArea {
              anchors.fill: parent
              onClicked: {
                if (section.outputs)
                  Pipewire.preferredDefaultAudioSink = row.modelData
                else
                  Pipewire.preferredDefaultAudioSource = row.modelData
              }
            }
          }
          Rectangle {
            id: bar
            width: parent.width
            height: 6
            color: Theme.surface
            Rectangle {
              width: parent.width * (row.audio ? Math.max(0, Math.min(1, row.audio.volume)) : 0)
              height: parent.height
              color: row.audio && row.audio.muted ? Theme.muted : Theme.accent
            }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              function set(x) {
                if (row.audio)
                  row.audio.volume = Model.volumeAt(x - 6, bar.width)
              }
              onPressed: (mouse) => set(mouse.x)
              onPositionChanged: (mouse) => { if (pressed) set(mouse.x) }
            }
          }
        }
      }
    }
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: Style.spacing

    Section {
      title: "Output"
      nodes: panel.devices.sinks
      outputs: true
    }
    Section {
      title: "Input"
      nodes: panel.devices.sources
      outputs: false
    }
  }
}
