import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.services

// The desktop background (ADR 0038): the palette's base colour, and the
// default wallpaper once the subarchy-wallpapers package has installed it,
// or the image named in ~/.local/state/subcult/wallpaper (the auto-wallpaper
// widget writes it; watched, so a change shows at once). The Wallpaper
// service watches that file and checks the image once for every output.
PanelWindow { // qmllint disable uncreatable-type
  id: background

  required property var modelData
  screen: modelData

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
    visible: Wallpaper.readable && status === Image.Ready
    source: Wallpaper.readable ? "file://" + Wallpaper.image : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    sourceSize.width: Math.ceil(background.modelData.width * background.modelData.devicePixelRatio)
    sourceSize.height: Math.ceil(background.modelData.height * background.modelData.devicePixelRatio)
  }
}
