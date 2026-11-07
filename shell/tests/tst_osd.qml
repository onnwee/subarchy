import QtQuick
import QtTest

import "../OsdModel.js" as Model

TestCase {
  name: "Osd"

  function test_brightnessFromMachine() {
    compare(Model.brightness("intel_backlight,backlight,12000,50%,24000"), 0.5)
    compare(Model.brightness("intel_backlight,backlight,24000,100%,24000\n"), 1)
    compare(Model.brightness(""), null)
    compare(Model.brightness("garbage"), null)
  }

  function test_volumeChangeShows() {
    verify(!Model.volumeChanged(null, { volume: 0.5, muted: false }), "the first reading is not a change")
    verify(Model.volumeChanged({ volume: 0.5, muted: false }, { volume: 0.55, muted: false }))
    verify(Model.volumeChanged({ volume: 0.5, muted: false }, { volume: 0.5, muted: true }))
    verify(!Model.volumeChanged({ volume: 0.5, muted: false }, { volume: 0.5, muted: false }))
  }
}
