import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "KeyboardLayout"

  function devices(keyboards) {
    return JSON.stringify({ mice: [], keyboards: keyboards })
  }

  function test_mainKeyboardCode() {
    const json = devices([
      { name: "video-bus", layout: "us", active_layout_index: 0, main: false },
      { name: "at-translated-set-2-keyboard", layout: "us,de", active_layout_index: 1, main: true }
    ])
    compare(Model.fromDevices(json), "DE")
  }

  function test_firstKeyboardWhenNoneIsMain() {
    compare(Model.fromDevices(devices([{ name: "kb", layout: "gb", active_layout_index: 0, main: false }])), "GB")
  }

  function test_eventKeyboardWins() {
    const json = devices([
      { name: "at-translated-set-2-keyboard", layout: "us,de", active_layout_index: 1, main: true },
      { name: "usb-keyboard", layout: "gb,fr", active_layout_index: 1, main: false }
    ])
    compare(Model.fromDevices(json, "usb-keyboard"), "FR", "the keyboard of the last activelayout event")
    compare(Model.fromDevices(json, "gone-keyboard"), "DE", "an unplugged event keyboard falls back")
    compare(Model.fromDevices(json, ""), "DE")
  }

  function test_powerButtonSkipped() {
    const json = devices([
      { name: "power-button", layout: "us", active_layout_index: 0, main: true },
      { name: "lid-switch", layout: "us", active_layout_index: 0, main: false },
      { name: "video-bus", layout: "us", active_layout_index: 0, main: false },
      { name: "sleep-button", layout: "us", active_layout_index: 0, main: false },
      { name: "hid-events-keyboard", layout: "us", active_layout_index: 0, main: false },
      { name: "virtual-keyboard", layout: "us", active_layout_index: 0, main: false },
      { name: "at-translated-set-2-keyboard", layout: "us,de", active_layout_index: 1, main: false }
    ])
    compare(Model.fromDevices(json), "DE", "a power button marked main is not the keyboard")
    compare(Model.fromDevices(devices([{ name: "power-button", layout: "gb", active_layout_index: 0, main: true }])), "GB",
            "when nothing else is left, the first device still counts")
  }

  function test_eventKeyboard() {
    compare(Model.eventKeyboard("usb-keyboard,English (US)"), "usb-keyboard")
    compare(Model.eventKeyboard("plain"), "plain")
    compare(Model.eventKeyboard(""), "")
  }

  function test_badInput() {
    compare(Model.fromDevices("not json"), "")
    compare(Model.fromDevices(devices([])), "")
    compare(Model.fromDevices(devices([{ name: "kb", layout: "us", active_layout_index: 5, main: true }])), "US")
  }
}
