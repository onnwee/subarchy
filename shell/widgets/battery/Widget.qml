import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Battery level and the power profile. Hidden without a laptop battery.
// Click cycles power-saver, balanced and performance.
BarWidget {
  id: root

  readonly property var device: UPower.displayDevice
  readonly property int percent: device ? Model.percent(device.percentage) : 0
  readonly property bool charging: device ? device.state === UPowerDeviceState.Charging : false
  readonly property string profile: PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver"
    : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"

  hidden: !Model.visible(device)
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.battery(root.percent, root.charging)
    label: root.percent + "%"
    color: root.percent <= 10 && !root.charging ? Theme.error : Theme.subtext
    tooltip: root.profile + (root.charging ? ", charging" : "")
    onClicked: {
      PowerProfiles.profile = PowerProfiles.profile === PowerProfile.PowerSaver ? PowerProfile.Balanced
        : PowerProfiles.profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance
        : PowerProfile.PowerSaver
    }
  }
}
