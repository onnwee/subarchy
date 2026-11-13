import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Ht3"

  readonly property var ht3: ({ name: "TOZO HT3", address: "AA:BB:CC:DD:EE:01", connected: true, batteryAvailable: true, battery: 0.89 })
  readonly property var renamed: ({ name: "Desk cans", deviceName: "TOZO-HT3", address: "AA:BB:CC:DD:EE:02", connected: true, batteryAvailable: false })
  readonly property var asleep: ({ name: "TOZO HT3", address: "AA:BB:CC:DD:EE:03", connected: false })
  readonly property var other: ({ name: "TOZO T10", address: "AA:BB:CC:DD:EE:04", connected: true })
  readonly property var lookalike: ({ name: "HT30 speaker", address: "AA:BB:CC:DD:EE:05", connected: true })
  readonly property var joined: ({ name: "tozoht3", address: "AA:BB:CC:DD:EE:06", connected: true })

  function test_which_devices() {
    verify(Model.isHt3(ht3))
    verify(Model.isHt3(renamed), "the remote name counts when the alias was changed")
    verify(!Model.isHt3(other))
    verify(!Model.isHt3(lookalike), "HT3 without TOZO is someone else's")
    verify(Model.isHt3(joined), "the owner's plugin matches HT3 and TOZO anywhere in the name")
    verify(Model.isHt3({ name: "TOZO HT3s" }))
    verify(!Model.isHt3({ name: "TOZO", deviceName: "HT3" }), "both words in one name")
    verify(!Model.isHt3(null))
    compare(Model.connected([other, asleep, lookalike]), null, "hidden without a connected HT3")
    compare(Model.connected([other, ht3, renamed]).address, renamed.address, "first by name")
    compare(Model.connected([ht3, { name: "TOZO HT3", connected: true }]).address, ht3.address, "a device without an address is skipped")
    compare(Model.connected(null), null)
  }

  // The helper's lines, as `subcult ht3 watch` prints them for the replies
  // PROTOCOL.md captured (89 %, transparency).
  function test_helper_lines() {
    compare(Model.event('{"event":"connected"}').event, "connected")
    const partial = Model.event('{"event":"state","battery":89}')
    compare(partial.battery, 89)
    compare(partial.mode, "")
    const full = Model.event('{"event":"state","battery":89,"mode":"transparency"}')
    compare(full.mode, "transparency")
    compare(Model.event('{"event":"state"}').battery, -1)
    compare(Model.event('{"event":"error","message":"The headphones are out of reach."}').message, "The headphones are out of reach.")
    for (const line of ['', 'null', '[]', '{}', '{"event":"set"}',
                        '{"event":"state","battery":101}', '{"event":"state","battery":-1}', '{"event":"state","battery":8.5}',
                        '{"event":"state","battery":"89"}', '{"event":"state","mode":"loud"}', '{"event":"state","mode":"toString"}',
                        '{"event":"error"}', '{"event":"error","message":""}'])
      compare(Model.event(line), null, line)
  }

  function test_texts() {
    compare(Model.modeText("anc"), "Noise cancelling")
    compare(Model.modeText("normal"), "Normal")
    compare(Model.modeText("unknown"), "Unknown")
    compare(Model.modeText(""), "")
    compare(Model.batteryText(89), "89 %")
    compare(Model.batteryText(0), "0 %")
    compare(Model.batteryText(-1), "")
    compare(Model.bluezBattery(ht3), 89)
    compare(Model.bluezBattery(renamed), -1)
    compare(Model.label(renamed), "Desk cans")
  }
}
