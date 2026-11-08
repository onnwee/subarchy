import QtQuick
import QtTest

import "../services/AlertsModel.js" as Model

TestCase {
  name: "Alerts"

  function run(readings) {
    let s = Model.initial()
    const fired = []
    for (const r of readings) {
      const out = Model.step(s, r)
      s = out.state
      fired.push(out.alerts.join("+"))
    }
    return fired
  }

  function test_lowOncePerCrossing() {
    compare(run([
      { percent: 25, onBattery: true }, { percent: 20, onBattery: true }, { percent: 19, onBattery: true },
      { percent: 21, onBattery: true }, { percent: 19, onBattery: true }
    ]), ["", "low", "", "", ""], "a wobble around 20 % does not fire again")
  }

  function test_rearmsAboveHysteresis() {
    compare(run([
      { percent: 20, onBattery: true }, { percent: 26, onBattery: true }, { percent: 20, onBattery: true }
    ]), ["low", "", "low"])
  }

  function test_criticalThenNotLowAgain() {
    compare(run([
      { percent: 15, onBattery: true }, { percent: 10, onBattery: true }, { percent: 9, onBattery: true },
      { percent: 12, onBattery: true }, { percent: 9, onBattery: true }, { percent: 16, onBattery: true }, { percent: 10, onBattery: true }
    ]), ["low", "critical", "", "", "", "", "critical"])
  }

  function test_nothingWhileCharging() {
    compare(run([
      { percent: 5, onBattery: false }, { percent: 5, onBattery: true }
    ]), ["", "critical"], "plugging in re-arms; unplugging at 5 % fires")
    compare(run([{ percent: 19, onBattery: false }]), [""])
  }

  function test_chargeRearms() {
    compare(run([
      { percent: 19, onBattery: true }, { percent: 19, onBattery: false }, { percent: 19, onBattery: true }
    ]), ["low", "", "low"])
  }

  function test_badReading() {
    compare(run([{ percent: NaN, onBattery: true }, { percent: "x", onBattery: true }]), ["", ""])
  }

  function test_message() {
    compare(Model.message("critical", 9)[0], "critical")
    verify(Model.message("low", 19)[2].indexOf("19%") >= 0)
  }
}
