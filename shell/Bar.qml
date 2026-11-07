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

  readonly property string mode: LayoutModel.modeFor(modelData.name, Config.bar, Quickshell.screens.map(s => s.name))
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

  // The widgets that actually loaded on this bar (used by the tests).
  function loadedIds() {
    const ids = []
    for (const section of [left, center, right])
      for (let i = 0; i < section.hosts.count; i++) {
        const h = section.hosts.itemAt(i) as WidgetHost
        if (h && h.widgetItem)
          ids.push(h.widgetId)
      }
    return ids
  }

  component Section: Row {
    property var ids: []
    property alias hosts: repeater
    spacing: Style.spacing
    height: Style.barHeight
    Repeater {
      id: repeater
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
    id: left
    ids: bar.sections.left
    anchors.left: parent.left
    anchors.leftMargin: Style.padding
  }

  Section {
    id: center
    ids: bar.sections.center
    anchors.horizontalCenter: parent.horizontalCenter
  }

  Section {
    id: right
    ids: bar.sections.right
    anchors.right: parent.right
    anchors.rightMargin: Style.padding
  }
}
