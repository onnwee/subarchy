pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "AltSwitchModel.js" as Model
import "Commons/HyprDispatch.js" as Dispatch

// Alt-Tab across all workspaces, most recently used first. Hyprland's
// bindings drive it through global shortcuts (next, prev, commit on Alt
// release); they arrive in key order on the shell's own connection, so a
// quick tap cannot commit before the first step. The IPC handler stays for
// tests. It remembers focus from Hyprland's events; the window list is read
// only while switching.
PanelWindow { // qmllint disable uncreatable-type
  id: sw

  property var history: []
  property var order: []
  property int index: -1
  readonly property var byAddress: {
    const m = {}
    for (const t of Hyprland.toplevels.values)
      m[t.address] = t
    return m
  }

  visible: index >= 0
  screen: place.screen
  WlrLayershell.namespace: "subcult-altswitch"
  WlrLayershell.layer: WlrLayer.Overlay
  exclusionMode: ExclusionMode.Ignore
  implicitWidth: Math.min(sw.order.length * 168 + Style.spacing, 900)
  implicitHeight: 52 + 2 * Style.spacing
  color: "transparent"

  OverlayScreen {
    id: place
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      if (Hyprland.activeToplevel)
        sw.history = Model.remember(sw.history, Hyprland.activeToplevel.address, 64)
    }
  }

  function step(n) {
    if (sw.index < 0) {
      place.open()
      Hyprland.refreshToplevels()
      sw.order = Model.order(Hyprland.toplevels.values.map(t => t.address), sw.history)
      sw.index = Model.start(sw.order, n)
    } else {
      sw.index = Model.next(sw.order, sw.index, n)
    }
  }

  function commit() {
    if (sw.index < 0)
      return
    if (sw.index < sw.order.length) {
      const d = Dispatch.window(sw.order[sw.index])
      if (d !== "")
        Hyprland.dispatch(d)
    }
    sw.cancel()
  }

  function cancel() {
    sw.index = -1
    sw.order = []
  }

  // A global-shortcut bind reports the key press and, later, its release.
  // Next and prev step on the press only. The Alt release bind reports a
  // release (or a press, from `hyprctl dispatch` and on Alt's next press),
  // so commit takes either; without an open switcher it does nothing.
  GlobalShortcut {
    appid: "subcult"
    name: "altswitch-next"
    description: "Alt-Tab: next window"
    onPressed: sw.step(1)
  }

  GlobalShortcut {
    appid: "subcult"
    name: "altswitch-prev"
    description: "Alt-Tab: previous window"
    onPressed: sw.step(-1)
  }

  GlobalShortcut {
    appid: "subcult"
    name: "altswitch-commit"
    description: "Alt-Tab: switch to the chosen window"
    onPressed: sw.commit()
    onReleased: sw.commit()
  }

  IpcHandler {
    target: "subcult.altswitch"
    function next(): void { sw.step(1) }
    function prev(): void { sw.step(-1) }
    function commit(): void { sw.commit() }
    function cancel(): void { sw.cancel() }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.mantle
    border.width: 1
    border.color: Theme.border

    ListView {
      id: list
      anchors.fill: parent
      anchors.margins: Style.spacing
      orientation: ListView.Horizontal
      spacing: Style.spacing
      clip: true
      interactive: false
      model: sw.order
      currentIndex: sw.index
      highlightFollowsCurrentItem: true
      highlightMoveDuration: 0

      delegate: Rectangle {
        id: card
        required property var modelData
        required property int index
        readonly property var toplevel: sw.byAddress[modelData] || null

        width: 160
        height: 52
        color: index === sw.index ? Theme.selection : Theme.base
        border.width: 1
        border.color: index === sw.index ? Theme.accent : Theme.surface

        Column {
          anchors.fill: parent
          anchors.margins: 6
          spacing: 2
          Text {
            width: parent.width
            text: card.toplevel && card.toplevel.lastIpcObject ? card.toplevel.lastIpcObject.class || "" : ""
            textFormat: Text.PlainText
            color: Theme.muted
            elide: Text.ElideRight
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
          Text {
            width: parent.width
            text: card.toplevel ? card.toplevel.title : ""
            textFormat: Text.PlainText
            color: Theme.text
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
        }
      }
    }
  }
}
