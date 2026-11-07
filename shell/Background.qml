import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// The desktop background (ADR 0038): the palette's base colour, and the
// default wallpaper once the subarchy-wallpapers package has installed it.
PanelWindow { // qmllint disable uncreatable-type
  id: background

  required property var modelData
  screen: modelData

  readonly property string wallpaper: "/usr/share/backgrounds/subarchy/01-acid-negative-space.png"
  property bool hasWallpaper: false

  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.namespace: "subcult-background"
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: Theme.base

  Image {
    anchors.fill: parent
    visible: background.hasWallpaper && status === Image.Ready
    source: background.hasWallpaper ? "file://" + background.wallpaper : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: background.modelData.width
    sourceSize.height: background.modelData.height
  }

  Process {
    running: true
    command: ["test", "-r", background.wallpaper]
    onExited: (code) => background.hasWallpaper = code === 0
  }
}
