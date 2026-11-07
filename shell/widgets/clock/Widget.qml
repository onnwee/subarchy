import QtQuick
import qs.Commons
import qs.Ui

// Date and time, as on sputnik's bar: "Sat 7 Nov 10:56 AM".
BarWidget {
  implicitWidth: label.implicitWidth

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    text: Qt.formatDateTime(Clock.now, "ddd d MMM h:mm AP")
    color: Theme.text
    font.family: Style.fontFamily
    font.pixelSize: Style.fontSize
  }
}
