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

  // Decoded at device pixels: the screen's logical size times its scale,
  // so it is sharp at a fractional scale (1.6 on sputnik). Not cached: the
  // decode is per output and a cached logical-size copy would be reused.
  Image {
    anchors.fill: parent
    visible: background.hasWallpaper && status === Image.Ready
    source: background.hasWallpaper ? "file://" + background.wallpaper : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    sourceSize.width: Math.ceil(background.modelData.width * background.modelData.devicePixelRatio)
    sourceSize.height: Math.ceil(background.modelData.height * background.modelData.devicePixelRatio)
  }

  Process {
    running: true
    command: ["test", "-r", background.wallpaper]
    onExited: (code) => background.hasWallpaper = code === 0
  }
}
