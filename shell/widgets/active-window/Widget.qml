import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// The focused window's title, elided. Hidden when nothing is focused.
BarWidget {
  id: root

  readonly property string title: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""

  hidden: title === ""
  implicitWidth: Math.min(label.implicitWidth, 320)

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    width: root.implicitWidth
    text: root.title
    elide: Text.ElideRight
    color: Theme.subtext
    font.family: Style.fontFamily
    font.pixelSize: Style.fontSize
  }
}
