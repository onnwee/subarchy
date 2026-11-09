import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import TestBluetooth
import "widgets/bluetooth"

ShellRoot {
  id: test
  property int step: 0
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
  function capture(name, next) {
    test.step = -1
    test.check(test.panel.grabToImage(result => {
      test.check(result.saveToFile(Quickshell.env("BT_PANEL_TEST") + "/" + name), "preview was not saved")
      next()
    }), "preview did not start")
  }
  Window {
    visible: true
    width: 360
    height: 660
    color: "#100b19"
    Loader { id: holder; x: 20; y: 20; sourceComponent: Component { Panel {} } }
  }
  FileView {
    id: stopped
    path: Quickshell.env("BT_PANEL_TEST") + "/stopped"
    watchChanges: true
    blockLoading: true
    onFileChanged: reload()
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (test.step === 12) {
        if (stopped.text().trim().split("\n").length < 2) return
        console.log("PASS: Bluetooth panel search, confirmation, PIN, cancel and cleanup")
        Qt.quit()
        return
      }
      const panel = test.panel
      const agent = panel.pairing
      const adapter = Bluetooth.defaultAdapter
      switch (test.step) {
      case 0:
        if (!agent.ready) return
        test.find(panel, "searchDevices").clicked()
        test.check(adapter.discovering && panel.searching, "search did not start")
        test.step++
        break
      case 1: case 4: case 7: {
        const pair = test.find(panel, "pairDevice")
        if (!pair) return
        pair.clicked()
        test.check(!adapter.discovering && !panel.searching, "our scan was not stopped for pairing")
        test.step++
        break
      }
      case 2:
        if (!agent.request) return
        test.check(agent.request.kind === "confirmation" && agent.request.code === "000123", "confirmation not shown")
        test.capture("confirmation.png", () => {
          test.find(panel, "acceptPairing").clicked()
          test.step = 3
        })
        break
      case 3:
        if (agent.busy) return
        test.check(agent.message === "Paired and trusted.", "confirmation did not finish")
        adapter.discovering = true // another client already owns a scan
        test.find(panel, "searchDevices").clicked()
        test.find(panel, "searchDevices").clicked()
        test.check(adapter.discovering, "stopped another client's scan")
        adapter.discovering = false
        test.find(panel, "searchDevices").clicked()
        test.step++
        break
      case 5:
        if (!agent.request) return
        test.check(agent.request.kind === "pin", "PIN prompt not shown")
        test.find(panel, "pairingCode").text = "fixture-pin"
        test.capture("pin-entry.png", () => {
          test.find(panel, "acceptPairing").clicked()
          test.step = 6
        })
        break
      case 6:
        if (agent.busy) return
        test.check(agent.message === "Paired and trusted.", "PIN response did not finish")
        test.check(test.find(panel, "pairingCode").text === "", "PIN retained after reply")
        test.find(panel, "searchDevices").clicked()
        test.step++
        break
      case 8:
        if (!agent.request) return
        test.check(agent.request.kind === "authorization", "authorization prompt not shown")
        test.find(panel, "cancelPairing").clicked()
        test.step++
        break
      case 9:
        if (agent.busy) return
        test.check(agent.message === "Pairing canceled.", "cancel was not reported")
        adapter.enabled = false
        test.step++
        break
      case 10:
        if (agent.ready) return
        test.check(!agent.busy && agent.request === null, "helper state survived closing")
        adapter.enabled = true
        test.step++
        break
      case 11:
        if (!agent.ready) return
        test.find(panel, "searchDevices").clicked()
        test.check(adapter.discovering, "final search did not start")
        holder.active = false
        test.check(!adapter.discovering, "closing the panel left its scan running")
        test.step++
      }
    }
  }
  Timer {
    interval: 10000
    running: true
    onTriggered: { console.error("FAIL: Bluetooth panel timed out at step " + test.step); Qt.exit(1) }
  }
}
