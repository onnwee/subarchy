import QtQuick
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// The SUBCULT mark at the left of the bar. A click opens the settings
// panel (bar layout, fonts, cursor, idle, motion: preview, apply, undo).
BarWidget {
  id: root
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.menu
    color: Theme.accent
    tooltip: "SUBCULT settings"
    onClicked: root.openPanel()
  }
}
