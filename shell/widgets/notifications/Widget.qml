import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "../../Commons/Glyphs.js" as Glyphs

// The notification bell: unread count; left click marks all read, right
// click toggles do-not-disturb. The history panel comes in stage 2.
BarWidget {
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.bell(Notifications.unread, Notifications.dnd)
    label: Notifications.unread > 0 ? String(Notifications.unread) : ""
    color: Notifications.unread > 0 ? Theme.text : Theme.subtext
    tooltip: Notifications.dnd ? "Do not disturb" : Notifications.unread + " unread"
    onClicked: (mouse) => {
      if (mouse.button === Qt.RightButton)
        Notifications.dnd = !Notifications.dnd
      else
        Notifications.markAllRead()
    }
  }
}
