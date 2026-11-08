import QtQuick
import Quickshell
import Quickshell.Hyprland
import "LayoutModel.js" as LayoutModel

// Which output an overlay (OSD, popups, polkit, Alt-Tab, launcher) shows
// on. Chosen when the overlay opens (the focused output) and again when
// outputs come or go (kept while it still exists), never on a focus move:
// following the pointer live recreated the window on every crossing.
// FALLBACK and nameless outputs are never chosen.
QtObject {
  id: root

  property string name: ""
  readonly property var screen: Quickshell.screens.find(s => s.name === root.name) || Quickshell.screens[0] || null

  function names() {
    return Quickshell.screens.map(s => s.name).filter(LayoutModel.isReal)
  }

  function focused() {
    return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  }

  // The overlay is opening: the focused output.
  function open() {
    root.name = LayoutModel.pickScreen(root.names(), root.focused(), "")
  }

  readonly property Connections outputs: Connections {
    target: Quickshell
    function onScreensChanged() {
      root.name = LayoutModel.pickScreen(root.names(), root.focused(), root.name)
    }
  }
}
