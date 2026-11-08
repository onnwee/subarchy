import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Bluetooth"

  readonly property var buds: ({ name: "Buds", address: "AA", paired: true, connected: true, state: 1, batteryAvailable: true, battery: 0.72 })
  readonly property var mouse: ({ name: "", deviceName: "MX Master", address: "BB", paired: true, connected: false, state: 0, batteryAvailable: false })
  readonly property var stranger: ({ name: "Phone", address: "CC", paired: false, bonded: false, connected: false, state: 0 })
  readonly property var bonded: ({ name: "Keys", address: "DD", paired: false, bonded: true, connected: false, state: 3 })

  function test_paired() {
    compare(Model.paired([stranger, mouse, buds, bonded, null]).map(Model.label), ["Buds", "Keys", "MX Master"], "connected first, then by name; unpaired dropped")
    compare(Model.paired([]), [])
  }

  function test_texts() {
    compare(Model.label(mouse), "MX Master", "the device name when the alias is empty")
    compare(Model.label({ address: "EE" }), "EE")
    compare(Model.stateText(buds), "Connected")
    compare(Model.stateText(mouse), "Not connected")
    compare(Model.stateText(bonded), "Connecting…")
    compare(Model.batteryText(buds), "72 %")
    compare(Model.batteryText(mouse), "")
    compare(Model.action(buds), "disconnect")
    compare(Model.action(mouse), "connect")
    compare(Model.action(bonded), "", "nothing while connecting")
  }
}
