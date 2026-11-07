import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.Commons
import "OsdModel.js" as Model
import "Commons/Glyphs.js" as Glyphs

// Volume, brightness and caps-lock feedback near the bottom of the focused
// output. Volume shows on its own when PipeWire reports a change; the
// brightness keys call `flash brightness` over IPC. Hidden after 1.5 s; the
// window exists only while shown.
PanelWindow { // qmllint disable uncreatable-type
  id: osd

  property string kind: ""
  property real value: 0
  property bool muted: false
  property var lastVolume: null

  readonly property var sink: Pipewire.defaultAudioSink

  visible: kind !== ""
  screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
  WlrLayershell.namespace: "subcult-osd"
  WlrLayershell.layer: WlrLayer.Overlay
  exclusionMode: ExclusionMode.Ignore
  anchors.bottom: true
  margins.bottom: 96 // qmllint disable unqualified unresolved-type
  implicitWidth: 280
  implicitHeight: 40
  color: "transparent"

  function show(k) {
    if (k === "brightness") {
      brightnessQuery.running = true
      return
    }
    if (k === "volume" && osd.sink && osd.sink.audio) {
      osd.value = osd.sink.audio.volume
      osd.muted = osd.sink.audio.muted
    }
    osd.kind = k
    hide.restart()
  }

  PwObjectTracker {
    objects: osd.sink ? [osd.sink] : []
  }

  Connections {
    target: osd.sink ? osd.sink.audio : null
    function onVolumeChanged() { osd.volumeEvent() }
    function onMutedChanged() { osd.volumeEvent() }
  }

  function volumeEvent() {
    const now = { volume: osd.sink.audio.volume, muted: osd.sink.audio.muted }
    if (Model.volumeChanged(osd.lastVolume, now))
      osd.show("volume")
    osd.lastVolume = now
  }

  Process {
    id: brightnessQuery
    command: ["brightnessctl", "-m"]
    stdout: StdioCollector {
      onStreamFinished: {
        const v = Model.brightness(text)
        osd.value = v === null ? 0 : v
        osd.muted = false
        osd.kind = "brightness"
        hide.restart()
      }
    }
  }

  Timer {
    id: hide
    interval: 1500
    onTriggered: osd.kind = ""
  }

  IpcHandler {
    target: "subcult.osd"
    // Not "show": the quickshell CLI reads that word as its own `ipc show`.
    function flash(kind: string): void {
      osd.show(kind)
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.mantle
    border.width: 1
    border.color: Theme.border

    Row {
      anchors.centerIn: parent
      spacing: Style.spacing

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: osd.kind === "volume" ? Glyphs.volume(osd.value, osd.muted)
          : osd.kind === "brightness" ? Glyphs.brightness(osd.value) : Glyphs.capsLock
        color: Theme.text
        font.family: Style.fontFamily
        font.pixelSize: Style.iconSize + 4
      }

      Rectangle {
        visible: osd.kind !== "capslock"
        anchors.verticalCenter: parent.verticalCenter
        width: 200
        height: 6
        color: Theme.surface
        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, osd.value))
          height: parent.height
          color: osd.muted ? Theme.muted : Theme.accent
        }
      }
    }
  }
}
