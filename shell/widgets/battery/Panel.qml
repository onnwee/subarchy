pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import qs.services
import "../dell-power/Model.js" as DellModel
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Charge, state, time left or to full, rate and health of the laptop
// battery, and the power profile with a switch. UPower and
// power-profiles-daemon push changes; nothing polls.
PanelBase {
  id: panel

  readonly property var device: UPower.displayDevice
  readonly property int percent: device ? Model.percent(device.percentage) : 0
  readonly property int deviceState: device ? Number(device.state) : 0
  readonly property string remaining: device ? Model.remainingText(deviceState, device.timeToEmpty, device.timeToFull) : ""
  readonly property string rate: device ? Model.rateText(device.changeRate, deviceState) : ""
  readonly property string health: device ? Model.healthText(device.healthPercentage) : ""
  readonly property string current: PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver"
    : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"

  readonly property bool dell: DellModel.visible(DellPower.report)
  property string saveError: ""

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  Component.onCompleted: DellPower.refresh()

  function setDisplay(key, value) {
    panel.saveError = panel.shell.config && panel.shell.config.set(key, value)
      ? "" : "Could not save the display setting. Check the bar configuration file."
  }

  function select(id) {
    PowerProfiles.profile = id === "power-saver" ? PowerProfile.PowerSaver : id === "performance" ? PowerProfile.Performance : PowerProfile.Balanced
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 8

    Row {
      visible: Model.visible(panel.device)
      spacing: 10
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Glyphs.battery(panel.percent, panel.deviceState === Model.CHARGING)
        color: panel.percent <= 10 && panel.deviceState !== Model.CHARGING ? Theme.error : Theme.text
        font.family: Style.fontFamily
        font.pixelSize: Style.fontSize + 14
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: panel.percent + " %"
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize + 8
          font.bold: true
        }
        Text {
          text: Model.stateText(panel.deviceState) + (panel.remaining ? ", " + panel.remaining : "")
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
      }
    }

    Text {
      visible: Model.visible(panel.device) && text !== ""
      text: [panel.rate, panel.health].filter(s => s !== "").join("   ")
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Theme.surface
    }

    DellControls {
      objectName: "dellControls"
      visible: panel.dell
      width: parent.width
    }

    Text {
      visible: !panel.dell
      text: "Power profile"
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
      font.bold: true
    }

    Flow {
      visible: !panel.dell
      width: parent.width
      spacing: 6
      Repeater {
        model: Model.profiles(PowerProfiles.hasPerformanceProfile)
        delegate: Choice {
          required property var modelData
          objectName: "powerProfile_" + modelData.id
          label: modelData.name
          active: modelData.id === panel.current
          onPicked: panel.select(modelData.id)
        }
      }
    }

    Text {
      visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None // qmllint disable missing-property
      width: parent.width
      text: "Performance is held back: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason) // qmllint disable missing-property
      wrapMode: Text.Wrap
      color: Theme.warning
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }

    Rectangle { width: parent.width; height: 1; color: Theme.surface }
    Text {
      text: "Bar display"
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
      font.bold: true
    }
    Text { text: "Battery"; color: Theme.subtext; font.family: Style.uiFontFamily; font.pixelSize: Style.fontSize - 1 }
    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: [{id: "icon", name: "Icon"}, {id: "icon-percentage", name: "Icon and percentage"}]
        delegate: Choice {
          required property var modelData
          objectName: "chargeDisplay_" + modelData.id
          label: modelData.name
          active: modelData.id === Model.chargeDisplay(panel.settings)
          onPicked: panel.setDisplay("chargeDisplay", modelData.id)
        }
      }
    }
    Text { text: "Power profile"; color: Theme.subtext; font.family: Style.uiFontFamily; font.pixelSize: Style.fontSize - 1 }
    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: [{id: "off", name: "Off"}, {id: "icon", name: "Icon"}, {id: "icon-text", name: "Icon and text"}]
        delegate: Choice {
          required property var modelData
          objectName: "profileDisplay_" + modelData.id
          label: modelData.name
          active: modelData.id === Model.profileDisplay(panel.settings)
          onPicked: panel.setDisplay("profileDisplay", modelData.id)
        }
      }
    }
    Text {
      visible: panel.saveError !== ""
      width: parent.width
      text: panel.saveError
      wrapMode: Text.Wrap
      color: Theme.warning
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }
  }
}
