import QtQuick
import qs.Commons

// A glyph in the bar that reacts to the pointer. Glyphs are Nerd Font
// codepoints, drawn in the monospace role. `scrolled` fires once per wheel
// notch (120 units of angleDelta): touchpads and high-resolution wheels send
// many smaller events, which add up to a step instead of each being one.
Item {
  id: button

  property string glyph
  property string label
  property color color: Theme.text
  property string tooltip

  signal clicked(var mouse)
  signal scrolled(int delta)

  // Vertical scroll not yet turned into a step.
  property real wheelRest: 0

  implicitWidth: row.implicitWidth + Style.padding
  implicitHeight: Style.barHeight

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 4
    Text {
      text: button.glyph
      visible: text !== ""
      color: mouse.containsMouse ? Theme.accent : button.color
      font.family: Style.fontFamily
      font.pixelSize: Style.iconSize
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: button.label
      textFormat: Text.PlainText
      visible: text !== ""
      color: button.color
      font.family: Style.fontFamily
      font.pixelSize: Style.fontSize
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: (m) => button.clicked(m)
    onWheel: (w) => {
      if (w.angleDelta.y === 0)
        return
      button.wheelRest += w.angleDelta.y
      while (Math.abs(button.wheelRest) >= 120) {
        const step = button.wheelRest > 0 ? 1 : -1
        button.wheelRest -= step * 120
        button.scrolled(step)
      }
    }
  }

  Tooltip {
    target: button
    text: button.tooltip
    shown: mouse.containsMouse && button.tooltip !== ""
  }
}
