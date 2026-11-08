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

  function test_evalLua() {
    compare(Model.evalLua("/usr/share/subcult"), "dofile([==[/usr/share/subcult/default/hypr/looknfeel.lua]==])")
    verify(Model.evalLua("/x]==]y").indexOf("]==]y") < 0, "a closing bracket in the path cannot end the string early")
  }
}
