import QtQuick
import Quickshell
import qs.Commons

// A small label under a bar item while the pointer rests on it.
PopupWindow {
  id: tip

  required property Item target
  property string text
  property bool shown: false

  visible: shown
  anchor.item: target // qmllint disable missing-property
  anchor.rect.y: target.height + 2 // qmllint disable unqualified unresolved-type
  implicitWidth: label.implicitWidth + 2 * Style.padding
  implicitHeight: label.implicitHeight + Style.padding
  color: Theme.mantle

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.color: Theme.border
    border.width: 1
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: tip.text
    color: Theme.text
    font.family: Style.fontFamily
    font.pixelSize: Style.fontSize
  }
}
