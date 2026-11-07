pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Commons/LayoutModel.js" as LayoutModel

// The bar on one output: opaque base colour, a 1 px line underneath, three
// sections of widgets. Full on the primary output and the laptop panel,
// Minimal elsewhere (sputnik's monitor-bar behaviour).
PanelWindow { // qmllint disable uncreatable-type
  id: bar

  required property var modelData
  screen: modelData

  readonly property string mode: LayoutModel.modeFor(modelData.name, Config.bar)
  readonly property var sections: LayoutModel.widgetsFor(Config.bar.layout, mode)

  WlrLayershell.namespace: "subcult-bar"
  anchors {
    top: true
    left: true
    right: true
  }
  implicitHeight: Style.barHeight
  color: Theme.base

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Theme.borderInactive
  }

  component Section: Row {
    property var ids: []
    spacing: Style.spacing
    height: Style.barHeight
    Repeater {
      model: parent.ids
      delegate: WidgetHost {
        required property string modelData
        widgetId: modelData
        mode: bar.mode
        screen: bar.modelData
      }
    }
  }

  Section {
    ids: bar.sections.left
    anchors.left: parent.left
    anchors.leftMargin: Style.padding
  }

  Section {
    ids: bar.sections.center
    anchors.horizontalCenter: parent.horizontalCenter
  }

  Section {
    ids: bar.sections.right
    anchors.right: parent.right
    anchors.rightMargin: Style.padding
  }
}
