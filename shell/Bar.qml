pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Commons/LayoutModel.js" as LayoutModel

// The bar on one output: opaque base colour, a 1 px line underneath, three
// sections of widgets. Full on the primary output and the laptop panel,
// Minimal elsewhere (sputnik's monitor-bar behaviour). The configured
// outputs match a connector name or the monitor's description.
PanelWindow { // qmllint disable uncreatable-type
  id: bar

  required property var modelData
  screen: modelData

  readonly property var monitors: Hyprland.monitors.values.map(m => ({ name: m.name, description: m.description }))
  readonly property var outputs: Quickshell.screens.map(s => ({ name: s.name, description: LayoutModel.describe(s, bar.monitors) }))
  readonly property string mode: LayoutModel.modeFor({ name: modelData.name, description: LayoutModel.describe(modelData, bar.monitors) }, Config.bar, bar.outputs)
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

  // The host of one widget on this bar, or null.
  function hostFor(id) {
    for (const section of [left, center, right])
      for (let i = 0; i < section.hosts.count; i++) {
        const h = section.hosts.itemAt(i) as WidgetHost
        if (h && h.widgetId === id)
          return h
      }
    return null
  }

  // The loaded widgets that are not hidden (no device, no data).
  function shownIds() {
    const ids = []
    for (const section of [left, center, right])
      for (let i = 0; i < section.hosts.count; i++) {
        const h = section.hosts.itemAt(i) as WidgetHost
        if (h && h.visible)
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
