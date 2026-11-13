import QtQuick
import QtTest

import "../Commons/HyprDispatch.js" as Dispatch

TestCase {
  name: "Dispatch"

  // Subarchy's Hyprland is configured in Lua: a dispatch is a Lua
  // dispatcher expression, not the old "workspace 3" text.
  function test_workspace() {
    compare(Dispatch.workspace(3), 'hl.dsp.focus({ workspace = "3" })')
  }

  function test_window() {
    compare(Dispatch.window("0x5a1b"), 'hl.dsp.focus({ window = hl.get_window("address:0x5a1b") })')
    compare(Dispatch.window("5a1b"), 'hl.dsp.focus({ window = hl.get_window("address:0x5a1b") })')
  }

  function test_windowRejectsInjection() {
    compare(Dispatch.window('0x1") }) os.execute("x'), "")
  }
}
