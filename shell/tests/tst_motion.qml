import QtQuick
import QtTest

import "../Commons/MotionModel.js" as Model

TestCase {
  name: "Motion"

  function test_mode() {
    compare(Model.mode('{"mode": "off"}'), "off")
    compare(Model.mode('{"mode": "on"}'), "on")
    compare(Model.mode('{"mode": "auto"}'), "auto")
    compare(Model.mode('{"mode": "reduced"}'), "auto", "an unknown value falls back to auto")
    compare(Model.mode(""), "auto", "no file is auto")
    compare(Model.mode("{ broken"), "auto")
  }

  function test_enabled() {
    verify(Model.enabled("on", true))
    verify(!Model.enabled("off", false))
    verify(Model.enabled("auto", false))
    verify(!Model.enabled("auto", true))
  }

  function test_command() {
    const off = Model.command(false)
    compare(off.slice(0, 2), ["hyprctl", "eval"])
    verify(off[2].indexOf("animations = { enabled = false }") >= 0)
    verify(off[2].indexOf("general") < 0 && off[2].indexOf("dofile") < 0, "turning motion off leaves gaps, borders and layout alone")
    compare(Model.command(true), ["hyprctl", "reload"])
  }
}
