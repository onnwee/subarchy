import QtQuick
import QtTest

import "../OsdModel.js" as Model

TestCase {
  name: "Osd"

  function test_brightnessFromSysfs() {
    compare(Model.level("12000\n", "24000\n"), 0.5)
    compare(Model.level("24000", "24000"), 1)
    compare(Model.level("30000", "24000"), 1)
    compare(Model.level("0", "24000"), 0)
  }

  function test_brightnessUnreadable() {
    compare(Model.level("", "24000"), null, "an empty read is not zero")
    compare(Model.level("garbage", "24000"), null)
    compare(Model.level("100", "0"), null)
    compare(Model.level("100", ""), null)
  }

  function test_volumeChangeShows() {
    verify(!Model.volumeChanged(null, { volume: 0.5, muted: false }), "the first reading is not a change")
    verify(Model.volumeChanged({ volume: 0.5, muted: false }, { volume: 0.55, muted: false }))
    verify(Model.volumeChanged({ volume: 0.5, muted: false }, { volume: 0.5, muted: true }))
    verify(!Model.volumeChanged({ volume: 0.5, muted: false }, { volume: 0.5, muted: false }))
  }

  function test_capsLabel() {
    compare(Model.capsLabel("0\n1\n"), "Caps Lock on", "any lit LED")
    compare(Model.capsLabel("0\n0\n"), "Caps Lock off")
    compare(Model.capsLabel(""), "Caps Lock", "no LED, state unknown")
    compare(Model.capsLabel("garbage\n"), "Caps Lock")
  }
}
