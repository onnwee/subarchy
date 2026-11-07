import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Commons/ConfigModel.js" as ConfigModel

// One widget slot in the bar (ADR 0068). Loads widgets/<dir>/Widget.qml,
// hands it mode, screen, settings and the shell services, and owns its
// panel: Panel.qml is loaded only while the panel is open.
Item {
  id: host

  property string widgetId
  property string mode: "full"
  property var screen
  property bool panelOpen: false

  readonly property var entry: WidgetIndex.entry(widgetId)
  readonly property var manifest: entry ? entry.manifest : null
  readonly property var settings: manifest
    ? ConfigModel.merge(manifest.settings || {}, (Config.bar.widgets || {})[widgetId] || {})
    : ({})
  readonly property var shellServices: ({ theme: Theme, power: Power, config: Config, style: Style, manifest: manifest })

  readonly property BarWidget widgetItem: widget.item as BarWidget
  readonly property PanelBase panelItem: panelLoader.item as PanelBase

  implicitWidth: widgetItem ? widgetItem.implicitWidth : 0
  implicitHeight: Style.barHeight
  visible: widgetItem !== null && !widgetItem.hidden

  property bool warned: false
  onEntryChanged: {
    if (!entry && widgetId !== "" && !warned && Object.keys(WidgetIndex.widgets).length > 0) {
      console.warn("subcult shell: unknown widget", widgetId)
      warned = true
    }
  }

  Loader {
    id: widget
    anchors.fill: parent
    active: host.entry !== null
    source: host.entry ? Qt.resolvedUrl("widgets/" + host.entry.dir + "/Widget.qml") : ""
    onLoaded: {
      const w = item as BarWidget
      if (!w) {
        console.warn("subcult shell:", host.widgetId, "Widget.qml is not a BarWidget")
        return
      }
      w.mode = Qt.binding(() => host.mode)
      w.screen = Qt.binding(() => host.screen)
      w.settings = Qt.binding(() => host.settings)
      w.shell = host.shellServices
      w.openPanel.connect(() => host.panelOpen = !host.panelOpen)
    }
  }

  PopupWindow {
    id: panel
    visible: host.panelOpen && panelLoader.status === Loader.Ready
    anchor.item: host
    anchor.rect.y: host.height
    implicitWidth: host.panelItem ? host.panelItem.implicitWidth : 1
    implicitHeight: host.panelItem ? host.panelItem.implicitHeight : 1
    color: "transparent"

    Loader {
      id: panelLoader
      active: host.panelOpen && host.entry !== null && host.manifest.panel === true
      source: active ? Qt.resolvedUrl("widgets/" + host.entry.dir + "/Panel.qml") : ""
      onLoaded: {
        const p = item as PanelBase
        if (!p) {
          console.warn("subcult shell:", host.widgetId, "Panel.qml is not a PanelBase")
          return
        }
        p.settings = Qt.binding(() => host.settings)
        p.shell = host.shellServices
        p.closePanel.connect(() => host.panelOpen = false)
      }
    }
  }
}
