import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Dell firmware power profile in the bar (ADR 0021; stage 3, off by
// default: `subcult hw apply` enables it on a Dell with the dell-pc
// platform profile through the machine layer of the bar config, or add
// "subcult.dell-power" to the layout). The glyph follows the
// power-profiles-daemon profile the firmware profile pairs with; the label
// names the firmware profile. Hidden on a machine without the firmware. A
// click opens the panel: profiles, charging mode and custom thresholds.
BarWidget {
  id: root

  readonly property var report: DellPower.report
  readonly property string active: Model.visible(report) ? Model.activeId(report.profiles) : ""
  readonly property string label: Model.label(report)

  hidden: !Model.visible(report)
  implicitWidth: button.implicitWidth

  Component.onCompleted: DellPower.refresh()

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.powerProfile(Model.osProfile(root.active))
    label: root.mode === "full" ? root.label : ""
    color: Theme.subtext
    tooltip: Model.tooltip(root.report)
    onClicked: root.openPanel()
  }
}
