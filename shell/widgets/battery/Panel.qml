pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
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

  implicitWidth: 300
  implicitHeight: column.implicitHeight

  function select(id) {
    PowerProfiles.profile = id === "power-saver" ? PowerProfile.PowerSaver : id === "performance" ? PowerProfile.Performance : PowerProfile.Balanced
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 8

    Row {
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
      visible: text !== ""
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

    Text {
      text: "Power profile"
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
      font.bold: true
    }

    Row {
      spacing: 6
      Repeater {
        model: Model.profiles(PowerProfiles.hasPerformanceProfile)
        delegate: Rectangle {
          id: choice
          required property var modelData
          readonly property bool active: choice.modelData.id === panel.current
          width: 92
          height: 28
          radius: 3
          color: active ? Theme.selection : Theme.base
          border.width: 1
          border.color: active ? Theme.accent : Theme.surface
          Text {
            anchors.centerIn: parent
            text: choice.modelData.name
            color: choice.active ? Theme.text : Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
          }
          MouseArea {
            anchors.fill: parent
            onClicked: panel.select(choice.modelData.id)
          }
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
  }
}
