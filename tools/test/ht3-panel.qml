import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import TestBluetooth
import qs.services
import "widgets/ht3"

// Drives the real HT3 panel and helper controller against a fake adapter
// and a stub `subcult ht3 watch` (tools/test/ht3-panel-test.sh).
ShellRoot {
  id: test
  property int step: 0
  property int waited: 0
  readonly property var panel: holder.item
  function check(value, message) {
    if (!value) { console.error("FAIL: " + message); Qt.exit(1) }
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (const child of item.children || []) {
      const found = find(child, name)
      if (found) return found
    }
    return null
  }
  function lines(view) {
    return view.text().trim().split("\n").filter(l => l !== "").length
  }
  Window {
    visible: true
    width: 320
    height: 200
    color: "#100b19"
    Loader { id: holder; x: 20; y: 20; sourceComponent: Component { Panel {} } }
  }
  FileView {
    id: started
    path: Quickshell.env("HT3_PANEL_TEST") + "/started"
    watchChanges: true
    blockLoading: true
    onFileChanged: reload()
  }
  FileView {
    id: stopped
    path: Quickshell.env("HT3_PANEL_TEST") + "/stopped"
    watchChanges: true
    blockLoading: true
    onFileChanged: reload()
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      const panel = test.panel
      switch (test.step) {
      case 0:
        // Opening the panel started the helper, which read the headset.
        if (!(Ht3.connected && Ht3.battery === 89 && Ht3.mode === "transparency")) return
        test.check(test.lines(started) === 1, "the helper did not start once with the panel")
        test.check(test.find(panel, "battery").text === "89 %", "battery not shown: " + test.find(panel, "battery").text)
        test.check(test.find(panel, "mode").text === "Transparency", "mode not shown: " + test.find(panel, "mode").text)
        test.check(test.find(panel, "status").text === "", "status shown while reading")
        test.step = -1
        test.check(panel.grabToImage(result => {
          test.check(result.saveToFile(Quickshell.env("HT3_PANEL_TEST") + "/ht3-panel.png"), "preview was not saved")
          holder.active = false
          test.step = 1
        }), "preview did not start")
        break
      case 1:
        // Closing it stopped the helper.
        if (test.lines(stopped) < 1) return
        test.check(!Ht3.active && !Ht3.connected, "the controller still holds the helper")
        holder.active = true
        test.step++
        break
      case 2:
        // The second run reads the battery, then fails as when the phone
        // app holds the channel: the error shows and the old reading goes.
        if (Ht3.message.indexOf("TOZO app") < 0) return
        test.check(test.find(test.panel, "status").text === Ht3.message, "the helper's error is not shown")
        test.check(Ht3.battery === -1 && Ht3.mode === "", "a reading stayed after the error")
        test.check(test.find(test.panel, "battery").text === "…", "the old battery stayed on screen")
        // The headset disconnects and reconnects with the panel open.
        Bluetooth.device.connected = false
        test.step++
        break
      case 3:
        test.check(!Ht3.active, "the helper is still held without a connected HT3")
        test.check(test.find(test.panel, "deviceName").text === "No HT3 connected", "panel without a device")
        Bluetooth.device.connected = true
        test.step++
        break
      case 4:
        // The reconnect started the helper again (the third, reading run).
        if (!(test.lines(started) === 3 && Ht3.connected && Ht3.battery === 89)) return
        test.check(Ht3.message === "", "the old error stayed after the reconnect")
        holder.active = false
        test.step++
        break
      case 5:
        if (test.lines(stopped) < 2) return
        Bluetooth.device.connected = false
        holder.active = true
        test.step++
        break
      case 6:
        // No HT3 connected: nothing starts.
        if (++test.waited < 10) return
        test.check(test.find(test.panel, "deviceName").text === "No HT3 connected", "panel without a device")
        test.check(test.lines(started) === 3 && !Ht3.active, "a helper started without a connected HT3")
        holder.active = false
        console.log("PASS: HT3 panel reading, error, reconnect, no device and helper cleanup")
        Qt.quit()
      }
    }
  }
  Timer {
    interval: 10000
    running: true
    onTriggered: { console.error("FAIL: HT3 panel timed out at step " + test.step); Qt.exit(1) }
  }
}
