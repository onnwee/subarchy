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

  function test_badInput() {
    compare(Model.fromDevices("not json"), "")
    compare(Model.fromDevices(devices([])), "")
    compare(Model.fromDevices(devices([{ name: "kb", layout: "us", active_layout_index: 5, main: true }])), "US")
  }
}
