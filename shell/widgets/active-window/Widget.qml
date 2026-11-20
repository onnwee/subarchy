import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The focused window's title, elided. Hidden when nothing is focused.
BarWidget {
  id: root

  readonly property string title: Model.title(Hyprland.activeToplevel)

  hidden: title === ""
  implicitWidth: Math.min(label.implicitWidth, 320)

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    width: root.implicitWidth
    text: root.title
    textFormat: Text.PlainText // titles come from any app or web page
    elide: Text.ElideRight
    color: Theme.subtext
    font.family: Style.fontFamily
    font.pixelSize: Style.fontSize
  }
}
