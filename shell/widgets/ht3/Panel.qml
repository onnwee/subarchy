pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Battery and noise mode of the connected HT3, read from the headset over
// its control channel by `subcult ht3 watch`. The helper starts when this
// panel opens and stops when it closes; audio stays connected throughout.
// The mode buttons ask the helper for Normal, ANC or Transparency; the
// panel shows a mode only once the headset's GET readback reports it.
// Volume moves the HT3's own PipeWire output, found by its exact address,
// up to 100 %; the default output is never changed. No EQ (issue #153).
PanelBase {
  id: panel

  readonly property var adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property var device: adapter && adapter.devices ? Model.connected(adapter.devices.values) : null
  // The address this panel opened the helper for; empty when none.
  property string held: ""
  readonly property var sink: panel.device ? Model.sinkFor(Pipewire.nodes ? Pipewire.nodes.values : [], panel.device.address) : null // qmllint disable missing-property
  readonly property var audio: panel.sink ? panel.sink.audio : null

  // Only the HT3's own output, and never above 100 %.
  function setVolume(v) {
    if (panel.audio)
      panel.audio.volume = Model.capVolume(v)
  }

  // Binds the HT3's output while the panel is open, so its volume is live.
  PwObjectTracker {
    objects: panel.sink ? [panel.sink] : []
  }

  // Follow the connected HT3: release the helper when it disconnects, and
  // start it again when it (or another HT3) connects while the panel is open.
  function hold() {
    const address = panel.device ? panel.device.address : ""
    if (address === panel.held)
      return
    if (panel.held !== "")
      Ht3.release()
    panel.held = address
    if (address !== "")
      Ht3.acquire(address)
  }

  onDeviceChanged: hold()
  Component.onCompleted: hold()
  Component.onDestruction: {
    if (panel.held !== "")
      Ht3.release()
  }

  implicitWidth: 280
  implicitHeight: column.implicitHeight

  component Reading: Item {
    id: row
    required property string glyph
    required property string title
    required property string value
    property string name
    height: 30
    Text {
      id: mark
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 22
      text: row.glyph
      color: Theme.accent
      font.family: Style.fontFamily
      font.pixelSize: Style.iconSize
    }
    Text {
      anchors.left: mark.right
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: row.title
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
    Text {
      objectName: row.name
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: row.value
      textFormat: Text.PlainText
      color: Theme.text
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
  }

  component ModeButton: Rectangle {
    id: choice
    required property var modelData
    readonly property bool active: Ht3.mode === modelData.id
    readonly property bool waiting: Ht3.pending === modelData.id
    objectName: "mode_" + modelData.id
    width: caption.implicitWidth + 18
    height: 28
    radius: 3
    enabled: Ht3.connected && Ht3.mode !== "" && Ht3.pending === ""
    color: active ? Theme.selection : Theme.base
    border.width: 1
    border.color: active || waiting || activeFocus ? Theme.accent : Theme.surface
    opacity: enabled || waiting ? 1 : 0.5
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: modelData.name
    Accessible.checked: active
    function pick() { Ht3.setMode(choice.modelData.id) }
    Accessible.onPressAction: pick()
    Keys.onSpacePressed: pick()
    Keys.onReturnPressed: pick()
    Text {
      id: caption
      anchors.centerIn: parent
      text: choice.waiting ? choice.modelData.name + " …" : choice.modelData.name
      textFormat: Text.PlainText
      color: choice.active ? Theme.text : Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }
    MouseArea {
      anchors.fill: parent
      onClicked: { choice.forceActiveFocus(); choice.pick() }
    }
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 4

    Text {
      objectName: "deviceName"
      width: parent.width
      text: panel.device ? Model.label(panel.device) : "No HT3 connected"
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: panel.device ? Theme.text : Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize + 1
      font.bold: panel.device !== null
    }

    Reading {
      visible: panel.held !== "" && panel.device !== null
      width: parent.width
      name: "battery"
      glyph: Glyphs.battery(Math.max(0, Ht3.battery), false)
      title: "Battery"
      value: Model.batteryText(Ht3.battery) || "…"
    }
    Reading {
      visible: panel.held !== "" && panel.device !== null
      width: parent.width
      name: "mode"
      glyph: Glyphs.headphones
      title: "Noise mode"
      value: Model.modeText(Ht3.mode) || "…"
    }
    Row {
      visible: panel.held !== "" && panel.device !== null
      spacing: 6
      Repeater {
        model: Model.choices
        delegate: ModeButton {}
      }
    }

    Reading {
      visible: panel.device !== null && panel.audio !== null
      width: parent.width
      name: "volume"
      glyph: panel.audio ? Glyphs.volume(panel.audio.volume, panel.audio.muted) : ""
      title: "Volume"
      value: panel.audio ? Model.volumeText(panel.audio.volume) : ""
    }
    Rectangle {
      id: bar
      objectName: "volumeBar"
      visible: panel.device !== null && panel.audio !== null
      width: parent.width
      height: 6
      color: Theme.surface
      Rectangle {
        width: parent.width * (panel.audio ? Model.capVolume(panel.audio.volume) : 0)
        height: parent.height
        color: panel.audio && panel.audio.muted ? Theme.subtext : Theme.accent
      }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        function set(x) {
          if (bar.width > 0)
            panel.setVolume((x - 6) / bar.width)
        }
        onPressed: (mouse) => set(mouse.x)
        onPositionChanged: (mouse) => { if (pressed) set(mouse.x) }
      }
    }
    Text {
      visible: panel.device !== null && panel.audio === null
      width: parent.width
      text: "Volume shows once the headphones' audio is connected."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Text {
      objectName: "status"
      visible: text !== ""
      width: parent.width
      text: panel.held === "" || !panel.device ? "Connect the headphones in the Bluetooth panel."
        : Ht3.message !== "" ? Ht3.message
        : !Ht3.connected ? "Connecting to the headphones…" : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Ht3.message !== "" ? Theme.warning : Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
  }
}
