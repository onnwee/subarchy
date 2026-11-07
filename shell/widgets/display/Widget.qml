import QtQuick
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// A monitor glyph naming this output; shown on Minimal bars too, as on
// sputnik. Its panel (display settings) comes in stage 2.
BarWidget {
  id: root

  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.display
    color: Theme.subtext
    tooltip: root.screen ? root.screen.name : ""
  }
}
