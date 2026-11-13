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
    compare(Model.event('{"event":"mode-set","mode":"anc"}').mode, "anc")
    const failed = Model.event('{"event":"mode-failed","mode":"normal","message":"The headphones did not confirm the new noise mode. Try again."}')
    compare(failed.mode, "normal")
    compare(failed.message, "The headphones did not confirm the new noise mode. Try again.")
    for (const line of ['', 'null', '[]', '{}', '{"event":"set"}',
                        '{"event":"mode-set"}', '{"event":"mode-set","mode":"adaptive"}', '{"event":"mode-set","mode":"toString"}',
                        '{"event":"mode-failed","mode":"anc"}', '{"event":"mode-failed","mode":"wind","message":"x"}',
                        '{"event":"state","battery":101}', '{"event":"state","battery":-1}', '{"event":"state","battery":8.5}',
                        '{"event":"state","battery":"89"}', '{"event":"state","mode":"loud"}', '{"event":"state","mode":"toString"}',
                        '{"event":"error"}', '{"event":"error","message":""}'])
      compare(Model.event(line), null, line)
  }

  function test_choices() {
    compare(Model.choices.map(c => c.id).join(" "), "normal anc transparency")
    verify(Model.settable("anc"))
    verify(!Model.settable("adaptive"), "PROTOCOL.md gives no SET for adaptive")
    verify(!Model.settable("unknown"))
  }

  // WirePlumber names a Bluetooth output bluez_output.<address>[.<n>].
  function test_sink_by_exact_address() {
    const own = { name: "bluez_output.AA_BB_CC_DD_EE_01.1", isSink: true, isStream: false }
    const older = { name: "bluez_output.aa_bb_cc_dd_ee_01.a2dp-sink", isSink: true, isStream: false }
    const otherHeadset = { name: "bluez_output.AA_BB_CC_DD_EE_011.1", isSink: true, isStream: false }
    const prefixOnly = { name: "bluez_output.AA_BB_CC_DD_EE_0", isSink: true, isStream: false }
    const speakers = { name: "alsa_output.pci-0000_00_1f.3.analog-stereo", isSink: true, isStream: false }
    const stream = { name: "bluez_output.AA_BB_CC_DD_EE_01.1", isSink: true, isStream: true }
    const input = { name: "bluez_input.AA_BB_CC_DD_EE_01.0", isSink: false, isStream: false }
    compare(Model.sinkFor([speakers, otherHeadset, prefixOnly, stream, input, own], ht3.address), own)
    compare(Model.sinkFor([older], ht3.address), older, "the address is matched in any case, with a profile suffix")
    compare(Model.sinkFor([speakers, otherHeadset, prefixOnly, stream, input], ht3.address), null, "no fallback to another output")
    compare(Model.sinkFor([own], ""), null)
    compare(Model.sinkFor([own], "AA:BB:CC:DD:EE"), null)
    compare(Model.sinkFor(null, ht3.address), null)
  }

  function test_volume_cap() {
    compare(Model.capVolume(0.75), 0.75)
    compare(Model.capVolume(1.4), 1, "capped at 100 %")
    compare(Model.capVolume(-0.2), 0)
    compare(Model.capVolume(NaN), 0)
    compare(Model.volumeText(0.75), "75 %")
    compare(Model.volumeText(0), "0 %")
    compare(Model.volumeText(undefined), "")
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
