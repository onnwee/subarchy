pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.services
import "services/NotificationsModel.js" as Model

// Popups at the top right, under the bar, on the output that was focused
// when the first of them appeared. Each goes after its app's timeout (the
// service keeps the timers; hovering a card pauses its own); critical ones
// stay until dismissed. The window exists only while there is something to
// show.
PanelWindow { // qmllint disable uncreatable-type
  id: window

  visible: Notifications.popups.length > 0
  screen: place.screen
  onVisibleChanged: if (visible) place.open()

  OverlayScreen {
    id: place
  }

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
      // ScriptModel keeps existing cards (and their timers) when one is
      // added or removed; a plain array would rebuild them all.
      model: ScriptModel {
        values: Notifications.popups
      }
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
            text: Model.plain(card.modelData.summary, Notifications.summaryCap)
            textFormat: Text.PlainText
            color: Theme.text
            elide: Text.ElideRight
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize + 1
            font.bold: true
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: Model.plain(card.modelData.body, Notifications.bodyCap)
            textFormat: Text.PlainText
            color: Theme.subtext
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Row {
            spacing: Style.spacing
            visible: Model.buttonActions(card.modelData.actions).length > 0
            Repeater {
              model: Model.buttonActions(card.modelData.actions)
              delegate: Rectangle {
                id: action
                required property var modelData
                width: label.implicitWidth + 2 * Style.padding
                height: label.implicitHeight + Style.padding
                color: Theme.base
                border.width: 1
                border.color: Theme.surface
                Text {
                  id: label
                  anchors.centerIn: parent
                  text: action.modelData.text
                  textFormat: Text.PlainText
                  color: Theme.text
                  font.family: Style.uiFontFamily
                  font.pixelSize: Style.fontSize
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: Notifications.invoke(card.modelData, action.modelData)
                }
              }
            }
          }
          Text {
            text: Model.plain(card.modelData.appName, Notifications.appNameCap)
            textFormat: Text.PlainText
            color: Theme.muted
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
        }

        MouseArea {
          anchors.fill: parent
          z: -1 // under the action buttons
          onClicked: Notifications.invoke(card.modelData, Model.defaultAction(card.modelData.actions))
        }

        // While read, the card stays.
        HoverHandler {
          onHoveredChanged: hovered ? Notifications.hold(card.modelData) : Notifications.release(card.modelData)
        }
      }
    }
  }
}
