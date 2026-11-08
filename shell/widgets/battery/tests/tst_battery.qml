import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Battery"

  function test_visible() {
    verify(Model.visible({ isPresent: true, isLaptopBattery: true }))
    verify(!Model.visible({ isPresent: true, isLaptopBattery: false }), "a mouse battery")
    verify(!Model.visible(null))
  }

  function test_percent() {
    compare(Model.percent(0.734), 73)
    compare(Model.percent(42), 42)
    compare(Model.percent(undefined), 0)
  }

  function test_texts() {
    compare(Model.stateText(1), "Charging")
    compare(Model.stateText(2), "Discharging")
    compare(Model.stateText(4), "Fully charged")
    compare(Model.stateText(5), "Not charging (charge limit)")
    compare(Model.stateText(0), "Unknown")
    compare(Model.duration(0), "")
    compare(Model.duration(1500), "25 min")
    compare(Model.duration(7500), "2 h 05 min")
    compare(Model.remainingText(2, 7500, 0), "2 h 05 min left")
    compare(Model.remainingText(2, 0, 0), "Estimating time left")
    compare(Model.remainingText(1, 0, 1800), "30 min to full")
    compare(Model.remainingText(4, 0, 0), "")
    compare(Model.rateText(12.34, 2), "−12.3 W")
    compare(Model.rateText(-8.1, 1), "+8.1 W")
    compare(Model.rateText(0.01, 2), "")
    compare(Model.healthText(87.6), "Health 88 %")
    compare(Model.healthText(0), "")
    compare(Model.profiles(false).map(p => p.id), ["power-saver", "balanced"])
    compare(Model.profiles(true).map(p => p.id), ["power-saver", "balanced", "performance"])
  }
}
