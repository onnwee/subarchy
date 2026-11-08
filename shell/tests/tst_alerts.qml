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

  // Thermal: one event per step, at a time in minutes.
  function thermalRun(steps) {
    let s = Model.thermalInitial()
    const fired = []
    for (const st of steps) {
      const out = Model.thermalStep(s, st.e, st.min * 60000)
      s = out.state
      fired.push(out.alert || "")
    }
    return fired
  }

  readonly property var hotUp: ({ zone: 0, type: "SKIN", kind: "hot", temp: 83000, tripTemp: 82050, direction: "up" })
  readonly property var hotDown: ({ zone: 0, type: "SKIN", kind: "hot", temp: 79000, tripTemp: 82050, direction: "down" })
  readonly property var critUp: ({ zone: 0, type: "SKIN", kind: "critical", temp: 88000, tripTemp: 87050, direction: "up" })
  readonly property var passiveUp: ({ zone: 2, type: "TCPU", kind: "passive", temp: 95000, tripTemp: 95000, direction: "up" })

  function test_thermalOncePerExcursion() {
    compare(thermalRun([{ e: hotUp, min: 0 }, { e: hotUp, min: 1 }, { e: hotDown, min: 2 }]), ["hot", "", ""],
      "a second up without a down does not fire")
  }

  function test_thermalCooldown() {
    compare(thermalRun([
      { e: hotUp, min: 0 }, { e: hotDown, min: 1 }, { e: hotUp, min: 2 }, { e: hotDown, min: 3 }, { e: hotUp, min: 25 }
    ]), ["hot", "", "", "", "hot"], "an up within 20 minutes of the last alert waits; after it fires")
    compare(thermalRun([{ e: critUp, min: 0 }, { e: critUp, min: 1 }, { e: hotUp, min: 1 }]), ["critical", "", "hot"],
      "hot and critical are armed apart")
  }

  function test_thermalIgnoresGovernorTrips() {
    compare(thermalRun([{ e: passiveUp, min: 0 }, { e: null, min: 0 }]), ["", ""])
  }

  function test_thermalZonesApart() {
    const other = Object.assign({}, hotUp, { zone: 5, type: "SEN4" })
    compare(thermalRun([{ e: hotUp, min: 0 }, { e: other, min: 0 }]), ["hot", "hot"])
  }

  function test_parseThermal() {
    const e = Model.parseThermal('{"zone":0,"type":"SKIN","trip":3,"kind":"hot","tripTemp":82050,"temp":83000,"direction":"up"}')
    compare(e.zone, 0)
    compare(e.kind, "hot")
    compare(e.direction, "up")
    compare(Model.parseThermal("not json"), null)
    compare(Model.parseThermal('{"direction": "up"}'), null, "no zone")
    compare(Model.parseThermal('[1]'), null)
  }

  function test_thermalMessage() {
    const m = Model.thermalMessage(hotUp)
    compare(m[0], "normal")
    compare(m[1], "Running hot")
    verify(m[2].indexOf("SKIN at 83 °C, past its hot trip at 82 °C") === 0, m[2])
    compare(Model.thermalMessage(critUp)[0], "critical")
    verify(Model.thermalMessage({ zone: 4, type: "", kind: "hot", temp: 70000, tripTemp: 0, direction: "up" })[2].indexOf("zone 4 at 70 °C.") === 0)
  }
}
