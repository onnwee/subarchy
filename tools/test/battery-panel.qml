import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import TestPower
import qs.Commons
import qs.services
import "widgets/battery" as Battery

ShellRoot {
  id: test
  property int phase: 0
  property int combination: 0
  property int ticks: 0
  TestCase { id: keyboard; when: false }
  readonly property var choices: ["off", "icon", "icon-text"]
  function check(value, message) {
    if (!value) { console.error("FAIL: " + message); Qt.exit(1) }
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (const child of item.children || []) {
      const result = find(child, name)
      if (result) return result
    }
    return null
  }
  function capture(item, name, next) {
    phase = -1
    check(item.grabToImage(result => {
      check(result.saveToFile(Quickshell.env("BATTERY_PANEL_TEST") + "/" + name), "capture failed")
      next()
    }), "capture did not start")
  }
  QtObject {
    id: configApi
    function set(key, value) { return Config.set("subcult.battery", key, value) }
  }
  Window {
    visible: true
    width: 380
    height: 860
    color: Theme.base
    Battery.Widget {
      id: widget
      x: 20; y: 10
      settings: (Config.bar.widgets || {})["subcult.battery"] || ({})
    }
    Loader {
      id: holder
      x: 20; y: 48
      sourceComponent: Component {
        Battery.Panel {
          settings: (Config.bar.widgets || {})["subcult.battery"] || ({})
          shell: ({config:configApi})
        }
      }
    }
  }
  Timer {
    interval: 35; running: true; repeat: true
    onTriggered: {
      test.check(++test.ticks < 400, "timed out at phase " + test.phase)
      const panel = holder.item
      if (!panel) return
      switch (test.phase) {
      case 0:
        test.check(Config.bar.layout.right.length === 1 && Config.bar.layout.right[0] === "subcult.battery", "duplicate legacy widget")
        test.find(panel, "chargeDisplay_" + (test.combination < 3 ? "icon" : "icon-percentage")).picked()
        test.find(panel, "profileDisplay_" + test.choices[test.combination % 3]).picked()
        test.phase++
        break
      case 1: {
        const charge = test.find(widget, "batteryCharge")
        const profile = test.find(widget, "batteryProfile")
        test.check(charge.label === (test.combination < 3 ? "" : "73%"), "charge display " + test.combination)
        test.check(profile.visible === (test.combination % 3 !== 0), "profile visibility " + test.combination)
        test.check(profile.label === (test.combination % 3 === 2 ? "Quiet" : ""), "profile label " + test.combination)
        test.capture(widget, "bar-" + test.combination + ".png", () => {
          test.combination++
          test.phase = test.combination < 6 ? 0 : 2
        })
        break
      }
      case 2: {
        const controls = test.find(panel, "dellControls")
        test.check(controls.custom.start === 60 && controls.custom.stop === 80, "custom firmware values lost")
        test.check(test.find(controls, "customThresholds").visible, "custom controls hidden")
        test.find(controls, "startIncrease").picked()
        test.find(controls, "applyThresholds").picked()
        test.check(DellPower.lastCharging.join(",") === "custom,61,80", "custom Apply arguments")
        const cool = test.find(controls, "dellProfile_cool")
        cool.forceActiveFocus()
        keyboard.keyClick(Qt.Key_Space)
        test.check(widget.label === "Cool", "Dell profile selection not reflected")
        test.capture(panel, "combined-dell.png", () => { test.phase = 3 })
        break
      }
      case 3:
        // A permission/capability failure remains visible and explains the gap.
        DellPower.report = {available:true, profiles:[{id:"quiet",active:true}], charging:{available:false}}
        test.phase++
        break
      case 4:
        test.check(test.find(panel, "chargingUnavailable").visible, "unavailable charging silently hidden")
        test.check(!test.find(panel, "customThresholds").visible, "stale custom editor")
        test.capture(panel, "charging-unavailable.png", () => { test.phase = 5 })
        break
      case 5:
        DellPower.report = {available:false}
        PowerProfiles.hasPerformanceProfile = false
        test.phase++
        break
      case 6:
        test.check(!test.find(panel, "dellControls").visible, "Dell controls shown on other hardware")
        test.check(test.find(panel, "powerProfile_performance") === null, "unsupported performance offered")
        test.find(panel, "powerProfile_power-saver").picked()
        test.check(PowerProfiles.profile === PowerProfile.PowerSaver, "generic power profile selection")
        // Recreate the panel, proving preferences come from the persisted config.
        holder.active = false
        holder.active = true
        test.phase++
        break
      case 7:
        test.check(panel.settings.chargeDisplay === "icon-percentage" && panel.settings.profileDisplay === "icon-text", "preferences did not survive panel reload")
        test.capture(panel, "generic-battery.png", () => { test.phase = 8 })
        break
      case 8:
        panel.shell = {config:{set: function() { return false }}}
        test.find(panel, "profileDisplay_off").picked()
        test.check(panel.saveError !== "", "failed save was silent")
        console.log("PASS: combined battery panel")
        Qt.quit()
        break
      }
    }
  }
}
