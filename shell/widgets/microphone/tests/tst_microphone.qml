import QtQuick
import QtTest
import "../Model.js" as Model
import "../../../Commons/Glyphs.js" as Glyphs

TestCase {
  name: "Microphone"

  function test_tooltipPrefersDescription() {
    compare(Model.tooltip({ description: "Built-in Mic", name: "alsa_input.pci" }, false), "Built-in Mic")
  }

  function test_tooltipFallsBackToName() {
    compare(Model.tooltip({ description: "", name: "alsa_input.pci" }, false), "alsa_input.pci")
  }

  function test_mutedIsMarked() {
    compare(Model.tooltip({ description: "Built-in Mic", name: "x" }, true), "Built-in Mic (muted)")
  }

  function test_noInputNoTooltip() {
    compare(Model.tooltip(null, false), "")
    compare(Model.tooltip(undefined, true), "")
  }

  function test_mutedGlyphDiffers() {
    verify(Glyphs.microphone(true) !== Glyphs.microphone(false))
  }
}
