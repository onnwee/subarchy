import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "../../Commons/Glyphs.js" as Glyphs

// The notification bell: unread count. A click opens the history panel and
// marks everything read; a right click toggles do-not-disturb.
BarWidget {
  id: root
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
      else {
        Notifications.markAllRead()
        root.openPanel()
      }
    }
  }
}
