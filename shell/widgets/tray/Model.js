.pragma library
// Status icons from apps (StatusNotifierItem): which items show and what a
// click does.

// Items whose status is not Passive. passive is the SystemTray.Status.Passive
// value; the QML passes it in because a library script cannot see the enum.
function visible(items, passive) {
  return (items || []).filter(i => i.status !== passive)
}

// Qt.LeftButton, Qt.RightButton and Qt.MiddleButton.
const LEFT = 1
const RIGHT = 2
const MIDDLE = 4

// "menu", "secondary" or "activate". Right click opens the app's menu, and so
// does a left click on an item that only has a menu (nm-applet); middle click
// is the app's secondary action.
function action(item, button) {
  if (item.hasMenu && (button === RIGHT || (button === LEFT && item.onlyMenu)))
    return "menu"
  if (button === MIDDLE)
    return "secondary"
  return "activate"
}
