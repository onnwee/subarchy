import QtQuick
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// The SUBCULT mark at the left of the bar. The menu it opens arrives with
// the launcher (ADR 0057).
BarWidget {
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.menu
    color: Theme.accent
    tooltip: "SUBCULT"
  }
}
