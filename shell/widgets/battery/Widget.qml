import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../dell-power/Model.js" as DellModel
import "../../Commons/Glyphs.js" as Glyphs

// One battery entry owns charge, power profiles and Dell charging controls.
// Both segments open the same panel; right click cycles supported profiles.
BarWidget {
  id: root

  readonly property var device: UPower.displayDevice
  readonly property bool hasBattery: Model.visible(device)
  readonly property int percent: device ? Model.percent(device.percentage) : 0
  readonly property bool charging: device ? device.state === UPowerDeviceState.Charging : false
  readonly property bool dell: DellModel.visible(DellPower.report)
  readonly property string profile: PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver"
    : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
  readonly property string label: dell ? DellModel.label(DellPower.report)
    : Model.profiles(true).find(p => p.id === root.profile).name
  readonly property string profileRole: dell ? DellModel.osProfile(DellModel.activeId(DellPower.report.profiles)) : profile
  readonly property string chargeDisplay: Model.chargeDisplay(settings)
  readonly property string profileDisplay: Model.profileDisplay(settings)
  readonly property string description: (hasBattery ? percent + "%, " + Model.stateText(device.state) + ". " : "")
    + (dell ? DellModel.tooltip(DellPower.report) : label)

  hidden: !hasBattery && (!dell || profileDisplay === "off")
  implicitWidth: buttons.implicitWidth
  Component.onCompleted: DellPower.refresh()

  function activate(mouse) {
    if (mouse.button !== Qt.RightButton) {
      root.openPanel()
      return
    }
    if (dell) {
      const choices = DellModel.profiles(DellPower.report)
      const index = choices.findIndex(p => p.active)
      if (choices.length > 0)
        DellPower.setProfile(choices[(index + 1) % choices.length].id)
    } else {
      PowerProfiles.profile = PowerProfiles.profile === PowerProfile.PowerSaver ? PowerProfile.Balanced
        : PowerProfiles.profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance
        : PowerProfile.PowerSaver
    }
  }

  Row {
    id: buttons
    anchors.verticalCenter: parent.verticalCenter
    IconButton {
      objectName: "batteryCharge"
      visible: root.hasBattery
      glyph: Glyphs.battery(root.percent, root.charging)
      label: root.chargeDisplay === "icon-percentage" ? root.percent + "%" : ""
      color: root.percent <= 10 && !root.charging ? Theme.error : Theme.subtext
      tooltip: root.description
      onClicked: (mouse) => root.activate(mouse)
    }
    IconButton {
      objectName: "batteryProfile"
      visible: root.profileDisplay !== "off"
      glyph: Glyphs.powerProfile(root.profileRole)
      label: root.profileDisplay === "icon-text" ? root.label : ""
      color: Theme.subtext
      tooltip: root.description
      onClicked: (mouse) => root.activate(mouse)
    }
  }
}
