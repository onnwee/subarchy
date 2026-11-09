import QtQuick
import qs.Commons

Rectangle {
  id: choice
  required property string label
  property bool active: false
  property bool checkable: true
  signal picked()

  width: caption.implicitWidth + 18
  height: 28
  radius: 3
  color: active ? Theme.selection : Theme.base
  border.width: 1
  border.color: activeFocus ? Theme.accent : active ? Theme.accent : Theme.surface
  opacity: enabled ? 1 : 0.5
  activeFocusOnTab: true
  Accessible.role: checkable ? Accessible.RadioButton : Accessible.Button
  Accessible.name: label
  Accessible.checked: active
  Accessible.onPressAction: picked()
  Keys.onSpacePressed: picked()
  Keys.onReturnPressed: picked()
  Keys.onEnterPressed: picked()

  Text {
    id: caption
    anchors.centerIn: parent
    text: choice.label
    textFormat: Text.PlainText
    color: choice.active ? Theme.text : Theme.subtext
    font.family: Style.uiFontFamily
    font.pixelSize: Style.fontSize - 1
  }
  MouseArea {
    anchors.fill: parent
    onClicked: { choice.forceActiveFocus(); choice.picked() }
  }
}
