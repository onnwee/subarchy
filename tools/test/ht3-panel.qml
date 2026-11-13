import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import TestBluetooth
import TestPipewire
import qs.services
import "widgets/ht3"

// Drives the real HT3 panel and helper controller against a fake adapter,
// fake PipeWire nodes and a stub `subcult ht3 watch`
// (tools/test/ht3-panel-test.sh).
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
    height: 300
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
    id: commands
    path: Quickshell.env("HT3_PANEL_TEST") + "/commands"
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
        test.check(test.find(panel, "mode_transparency").active && !test.find(panel, "mode_anc").active, "the read mode's button is not the active one")
        test.check(test.find(panel, "mode_anc").enabled, "mode buttons disabled with a mode read")
        // Volume: the HT3's own node by its address, not the default output
        // or the other headset.
        test.check(test.find(panel, "volume").text === "75 %", "HT3 volume not shown: " + test.find(panel, "volume").text)
        panel.setVolume(1.4)
        test.check(Pipewire.ht3.audio.volume === 1, "volume not capped at 100 %: " + Pipewire.ht3.audio.volume)
        test.check(test.find(panel, "volume").text === "100 %", "volume text did not follow")
        panel.setVolume(0.5)
        test.check(Pipewire.ht3.audio.volume === 0.5, "volume not set")
        test.check(Pipewire.speakers.audio.volume === 0.4 && Pipewire.otherHeadset.audio.volume === 0.3, "another output's volume moved")
        test.check(Pipewire.preferredDefaultAudioSink === null && Pipewire.defaultAudioSink === Pipewire.speakers, "the default output changed")
        test.check(Pipewire.tracked.length === 1 && Pipewire.tracked[0] === Pipewire.ht3, "the panel tracks other nodes")
        // ANC: the request alone shows nothing new.
        test.find(panel, "mode_anc").pick()
        test.check(Ht3.pending === "anc" && Ht3.mode === "transparency", "the mode moved before the readback")
        test.check(test.find(panel, "mode").text === "Transparency", "the panel showed the new mode before the readback")
        test.check(!test.find(panel, "mode_normal").enabled, "buttons stay enabled while a change waits")
        test.step = 10
        break
      case 10:
        // The stub's readback reports ANC, then confirms the change.
        if (Ht3.pending !== "" || commands.text().trim() === "") return
        test.check(commands.text().trim() === "mode anc", "the helper got " + JSON.stringify(commands.text()))
        test.check(Ht3.mode === "anc" && test.find(panel, "mode").text === "Noise cancelling", "ANC not shown after its readback")
        test.check(test.find(panel, "mode_anc").active && test.find(panel, "mode_normal").enabled, "buttons did not follow the readback")
        // Normal: the stub's readback does not confirm it.
        test.find(panel, "mode_normal").pick()
        test.step = 11
        break
      case 11:
        if (Ht3.pending !== "") return
        test.check(Ht3.mode === "anc", "a refused change moved the mode")
        test.check(test.find(panel, "status").text.indexOf("did not confirm") >= 0, "the refusal is not shown: " + test.find(panel, "status").text)
        test.check(Ht3.connected && Ht3.battery === 89, "a refused change dropped the channel")
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
        test.check(Ht3.pending === "", "a pending change survived the reconnect")
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
        console.log("PASS: HT3 panel reading, mode readback, volume, error, reconnect, no device and helper cleanup")
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
