import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Workspaces"

  readonly property var spaces: [
    { id: 1, monitor: "eDP-1", windows: 2, active: false },
    { id: 3, monitor: "eDP-1", windows: 0, active: true },
    { id: 5, monitor: "DP-3", windows: 1, active: true }
  ]

  function test_slotsMarksActiveAndOccupied() {
    const s = Model.slots(spaces, "eDP-1", 10)
    compare(s.length, 10)
    compare(s[0], { id: 1, occupied: true, active: false })
    compare(s[1], { id: 2, occupied: false, active: false })
    compare(s[2], { id: 3, occupied: false, active: true })
    compare(s[9].id, 10)
  }

  function test_slotsOtherMonitor() {
    const s = Model.slots(spaces, "eDP-1", 10)
    compare(s[4], { id: 5, occupied: true, active: false }, "another output's active workspace is not active here")
    compare(Model.slots(spaces, "DP-3", 10)[4].active, true)
  }

  function test_slotsIgnoresSpecialAndHigh() {
    const s = Model.slots([{ id: -98, monitor: "eDP-1", windows: 1, active: false },
                           { id: 12, monitor: "eDP-1", windows: 1, active: true }], "eDP-1", 10)
    compare(s.filter(x => x.occupied || x.active).length, 0)
  }
}
