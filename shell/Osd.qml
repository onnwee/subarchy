import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.Commons
import "OsdModel.js" as Model
import "Commons/Glyphs.js" as Glyphs

// Volume, brightness, caps-lock and workspace-switch feedback near the
// bottom of the focused output. Volume shows on its own when PipeWire reports a change. The
// brightness keys arrive as global shortcuts: brightnessctl sets the level,
// then the OSD reads it back from sysfs. Hidden after 1.5 s; the window
// exists only while shown, on the output that was focused when it opened.
PanelWindow { // qmllint disable uncreatable-type
  id: osd

  property string kind: ""
  property real value: 0
  property bool muted: false
  property string label: ""
  property int lastWorkspace: -1
  // The backlight's sysfs folder, found once at start; empty without one.
  property string backlight: ""

  readonly property var sink: Pipewire.defaultAudioSink
  // A new sink's first reading is not a change of volume; one that is
  // already loaded gives its reading as the baseline at once.
  readonly property var volume: Model.volumeTracker()
  onSinkChanged: osd.volume.switchTo(osd.sink)

  visible: kind !== ""
  screen: place.screen
  // No clicks: the OSD sits over whatever the pointer is on.
  mask: Region {}
  WlrLayershell.namespace: "subcult-osd"
  WlrLayershell.layer: WlrLayer.Overlay
  exclusionMode: ExclusionMode.Ignore
  anchors.bottom: true
  margins.bottom: 96 // qmllint disable unqualified unresolved-type missing-property
  implicitWidth: 280
  implicitHeight: 40
  color: "transparent"

  function show(k) {
    if (osd.kind === "")
      place.open()
    if (k === "brightness") {
      const v = osd.brightnessLevel()
      if (v === null)
        return
      osd.value = v
      osd.muted = false
    } else if (k === "workspace") {
      const ws = Hyprland.focusedWorkspace
      osd.label = Workspaces.title(ws ? ws.id : osd.lastWorkspace)
    } else if (k === "volume" && osd.sink && osd.sink.audio) {
      osd.value = osd.sink.audio.volume
      osd.muted = osd.sink.audio.muted
    }
    osd.kind = k
    hide.restart()
  }

  OverlayScreen {
    id: place
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
    if (osd.volume.reading(osd.sink))
      osd.show("volume")
  }

  // sysfs does not report changes, so the level is read again each time.
  function brightnessLevel() {
    if (osd.backlight === "")
      return null
    levelFile.reload()
    levelFile.waitForJob()
    return Model.level(levelFile.text(), maxFile.text())
  }

  // One write at a time: a press (or key repeat) while one runs is dropped.
  // Without a backlight it does nothing: brightnessctl with no -d would
  // change the first LED instead, such as Caps Lock's.
  function stepBrightness(change) {
    if (brightnessSet.running || osd.backlight === "")
      return
    brightnessSet.command = ["brightnessctl", "-q", "-d", osd.backlight.split("/").pop(), "set", change]
    brightnessSet.running = true
  }

  GlobalShortcut {
    appid: "subcult"
    name: "brightness-up"
    description: "Brightness up"
    onPressed: osd.stepBrightness("5%+")
  }

  GlobalShortcut {
    appid: "subcult"
    name: "brightness-down"
    description: "Brightness down"
    onPressed: osd.stepBrightness("5%-")
  }

  // Caps Lock arrives when the key is let go (default/hypr/bindings.lua).
  // The keyboard's LED says which way it went, a moment after the key.
  GlobalShortcut {
    appid: "subcult"
    name: "capslock"
    description: "Caps Lock indicator"
    onPressed: capsDelay.restart()
    onReleased: capsDelay.restart()
  }

  Timer {
    id: capsDelay
    interval: 80
    onTriggered: capsLeds.running = true
  }

  Process {
    id: capsLeds
    command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null; true"]
    stdout: StdioCollector {
      onStreamFinished: {
        osd.label = Model.capsLabel(text)
        osd.show("capslock")
      }
    }
  }

  Process {
    id: brightnessSet
    onExited: osd.show("brightness")
  }

  Process {
    running: true
    command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] && { echo \"$d\"; exit; }; done"]
    stdout: StdioCollector {
      onStreamFinished: osd.backlight = text.trim()
    }
  }

  FileView {
    id: levelFile
    path: osd.backlight === "" ? "" : osd.backlight + "/brightness"
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: maxFile
    path: osd.backlight === "" ? "" : osd.backlight + "/max_brightness"
    blockLoading: true
    printErrors: false
  }

  // A workspace switch shows its name for a moment (rice port:
  // subcult.workspace-osd). The first focus at start is not a switch.
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      const ws = Hyprland.focusedWorkspace
      if (!ws || ws.id <= 0)
        return
      const first = osd.lastWorkspace < 0
      osd.lastWorkspace = ws.id
      if (!first)
        osd.show("workspace")
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
      if (kind === "capslock")
        osd.label = Model.capsLabel("")
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
        visible: osd.kind !== "workspace"
        anchors.verticalCenter: parent.verticalCenter
        text: osd.kind === "volume" ? Glyphs.volume(osd.value, osd.muted)
          : osd.kind === "brightness" ? Glyphs.brightness(osd.value) : Glyphs.capsLock
        color: Theme.text
        font.family: Style.fontFamily
        font.pixelSize: Style.iconSize + 4
      }

      Text {
        visible: osd.kind === "workspace" || osd.kind === "capslock"
        anchors.verticalCenter: parent.verticalCenter
        text: osd.label
        textFormat: Text.PlainText
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize + 3
        font.bold: true
      }

      Rectangle {
        visible: osd.kind !== "capslock" && osd.kind !== "workspace"
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
