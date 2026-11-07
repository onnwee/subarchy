import QtQuick
import QtTest

import "../Commons/Glyphs.js" as Glyphs
import "../widgets/battery/Model.js" as Battery

TestCase {
  name: "Glyphs"

  function test_batteryBands() {
    compare(Glyphs.battery(5, false), Glyphs.battery(9, false))
    verify(Glyphs.battery(5, false) !== Glyphs.battery(95, false))
    verify(Glyphs.battery(50, true) !== Glyphs.battery(50, false), "charging looks different")
    compare(Glyphs.battery(100, false), Glyphs.battery(97, false))
    compare(Glyphs.battery(-3, false), Glyphs.battery(0, false))
  }

  function test_volumeBands() {
    verify(Glyphs.volume(0.5, true) !== Glyphs.volume(0.5, false), "muted looks different")
    compare(Glyphs.volume(0, false), Glyphs.volume(0, true), "silent is shown as muted")
    verify(Glyphs.volume(0.2, false) !== Glyphs.volume(0.9, false))
    compare(Glyphs.volume(1.4, false), Glyphs.volume(1.0, false), "over-amplified is the loudest band")
  }

  function test_wifiBands() {
    verify(Glyphs.wifi(0.1) !== Glyphs.wifi(0.9))
    compare(Glyphs.wifi(0.95), Glyphs.wifi(0.8))
  }

  function test_otherGlyphs() {
    verify(Glyphs.microphone(true) !== Glyphs.microphone(false))
    verify(Glyphs.ethernet(true) !== Glyphs.ethernet(false))
    verify(Glyphs.bluetooth(true, 1) !== Glyphs.bluetooth(true, 0))
    verify(Glyphs.bluetooth(false, 0) !== Glyphs.bluetooth(true, 0))
    verify(Glyphs.powerProfile("power-saver") !== Glyphs.powerProfile("performance"))
  }

  function test_batteryHiddenWithoutDevice() {
    verify(!Battery.visible(null))
    verify(!Battery.visible({ isPresent: false, isLaptopBattery: true }))
    verify(!Battery.visible({ isPresent: true, isLaptopBattery: false }), "a mouse or UPS is not the laptop battery")
    verify(Battery.visible({ isPresent: true, isLaptopBattery: true }))
  }

  function test_batteryPercent() {
    compare(Battery.percent(0.42), 42)
    compare(Battery.percent(42), 42)
    compare(Battery.percent(1), 100)
  }
}
