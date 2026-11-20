import QtQuick
import QtTest
import "../Model.js" as Model
import "../../../Commons/Glyphs.js" as Glyphs

TestCase {
  name: "Display"

  function test_tooltipNamesTheOutput() {
    compare(Model.tooltip({ name: "eDP-1" }), "eDP-1")
  }

  function test_noScreenNoTooltip() {
    compare(Model.tooltip(null), "")
    compare(Model.tooltip({}), "")
  }

  function test_hasAGlyph() {
    verify(Glyphs.display.length > 0)
  }
}
