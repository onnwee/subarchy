pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.Commons
import qs.services

// Popups at the top right of the focused output, under the bar. They go
// after five seconds; critical ones stay until dismissed. The window
// exists only while there is something to show.
PanelWindow { // qmllint disable uncreatable-type
  id: window

  visible: Notifications.popups.length > 0
  screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]

  WlrLayershell.namespace: "subcult-notifications"
  WlrLayershell.layer: WlrLayer.Overlay
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    right: true
  }
  margins.top: Style.barHeight + Style.spacing // qmllint disable unqualified unresolved-type missing-property
  margins.right: Style.spacing // qmllint disable unqualified unresolved-type missing-property
  implicitWidth: 360
  implicitHeight: column.implicitHeight
  color: "transparent"

  Column {
    id: column
    width: parent.width
    spacing: Style.spacing

    Repeater {
      model: Notifications.popups
      delegate: Rectangle {
        id: card
        required property var modelData
        readonly property bool critical: modelData.urgency === NotificationUrgency.Critical

        width: column.width
        implicitHeight: content.implicitHeight + 2 * Style.spacing
        color: Theme.mantle
        border.width: 1
        border.color: critical ? Theme.error : Theme.border

        Column {
          id: content
          x: Style.spacing
          y: Style.spacing
          width: parent.width - 2 * Style.spacing
          spacing: 2

          Text {
            width: parent.width
            text: card.modelData.summary
            color: Theme.text
            elide: Text.ElideRight
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize + 1
            font.bold: true
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: card.modelData.body
            textFormat: Text.StyledText
            color: Theme.subtext
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Text {
            text: card.modelData.appName
            color: Theme.muted
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: Notifications.dismiss(card.modelData)
        }

        Timer {
          running: !card.critical
          interval: 5000
          onTriggered: Notifications.expire(card.modelData)
        }
      }
    }
  }
}
