import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "DellPower"

  readonly property string sample: '{"available": true, "profiles": [{"id": "quiet", "active": false}, {"id": "balanced", "active": true}],'
    + ' "charging": {"available": true, "modes": [{"id": "adaptive", "active": false}, {"id": "custom", "active": true}],'
    + ' "custom": {"start": 60, "stop": 80, "startMin": 50, "startMax": 95, "stopMin": 55, "stopMax": 100, "step": 5}}}'

  function test_parseAndVisible() {
    verify(Model.visible(Model.parse(sample)))
    verify(!Model.visible(Model.parse('{"available": false}')), "no firmware")
    verify(!Model.visible(Model.parse("not json")))
    verify(!Model.visible(null))
  }

  function test_names() {
    const r = Model.parse(sample)
    compare(Model.label(r), "Balanced")
    compare(Model.profiles(r).map(p => p.name), ["Quiet", "Balanced"])
    compare(Model.modes(r).map(m => m.name), ["Adaptive", "Custom"])
    compare(Model.activeId(Model.modes(r)), "custom")
    compare(Model.tooltip(r), "Dell: Balanced, charging custom 60–80 %")
    compare(Model.osProfile("quiet"), "power-saver")
    compare(Model.osProfile("cool"), "power-saver")
    compare(Model.osProfile("performance"), "performance")
    compare(Model.osProfile("balanced"), "balanced")
    compare(Model.label(Model.parse('{"available": false}')), "")
  }

  function test_stepped() {
    const c = Model.custom(Model.parse(sample))
    compare(Model.stepped(c, 60, 80, "start", 1), { start: 65, stop: 80 })
    compare(Model.stepped(c, 60, 80, "stop", -1), { start: 60, stop: 75 })
    compare(Model.stepped(c, 50, 80, "start", -1), { start: 50, stop: 80 }, "at the minimum")
    compare(Model.stepped(c, 60, 100, "stop", 1), { start: 60, stop: 100 }, "at the maximum")
    compare(Model.stepped(c, 75, 80, "start", 1), { start: 80, stop: 85 }, "the stop follows to keep the gap")
    compare(Model.stepped(c, 75, 80, "stop", -1), { start: 70, stop: 75 }, "the start follows to keep the gap")
    compare(Model.stepped(c, 95, 100, "start", 1), { start: 95, stop: 100 }, "nothing moves past the ends")
  }
}
