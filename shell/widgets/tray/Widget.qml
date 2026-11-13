import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons
import qs.Ui

// Status icons from apps (StatusNotifierItem). Left click activates, or
// opens the menu of an item that only has a menu (nm-applet); middle click
// is the app's secondary action; right click opens the app's menu. An item
// whose status is Passive (idle, by the StatusNotifierItem spec) is hidden
// until the app sets it Active or NeedsAttention again.
BarWidget {
  id: root

  readonly property var items: SystemTray.items ? SystemTray.items.values.filter(i => i.status !== Status.Passive) : [] // qmllint disable missing-property

  hidden: items.length === 0
  implicitWidth: row.implicitWidth

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6

    Repeater {
      // ScriptModel keeps existing slots (and an open menu) when an item's
      // status changes; the filtered array is new on every change, and a
      // plain array would rebuild them all.
      model: ScriptModel {
        values: root.items
      }
      delegate: Item {
        id: slot
        required property var modelData
        width: Style.iconSize + 2
        height: Style.barHeight

        IconImage {
          anchors.centerIn: parent
          implicitSize: Style.iconSize
          source: slot.modelData.icon
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onClicked: (mouse) => {
            const item = slot.modelData
            if (item.hasMenu && (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && item.onlyMenu)))
              menu.open()
            else if (mouse.button === Qt.MiddleButton)
              item.secondaryActivate()
            else
              item.activate()
          }
        }

        QsMenuAnchor {
          id: menu
          menu: slot.modelData.menu
          anchor.item: slot
          anchor.rect.y: slot.height
        }
      }
    }
  }
}
