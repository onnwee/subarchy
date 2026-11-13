import QtQuick
import qs.Commons
import qs.Ui
import "Commons/ConfigModel.js" as ConfigModel

// One widget slot in the bar (ADR 0068). Loads widgets/<dir>/Widget.qml,
// hands it mode, screen, settings and the shell services. Its panel is
// shown by PanelOverlay (one at a time, on this bar's output): Panel.qml
// is loaded only while the panel is open.
Item {
  id: host

  property string widgetId
  property string mode: "full"
  property var screen
  readonly property bool panelOpen: Panels.host === host

  readonly property var entry: WidgetIndex.entry(widgetId)
  readonly property var manifest: entry ? entry.manifest : null
  readonly property var settings: manifest
    ? ConfigModel.merge(manifest.settings || {}, (Config.bar.widgets || {})[widgetId] || {})
    : ({})
  // What the widget gets as `shell` (ADR 0068): power and config are bound
  // to this widget, so it asks for its own timers by name and can write
  // only its own settings.
  readonly property var shellServices: ({ theme: Theme, style: Style, power: powerApi, config: configApi, manifest: manifest })

  QtObject {
    id: powerApi
    readonly property bool onBattery: Power.onBattery
    function interval(timerName: string): int {
      return Power.interval(host.entry ? host.entry.manifest : null, timerName)
    }
  }

  QtObject {
    id: configApi
    function set(key: string, value: var): bool {
      return Config.set(host.widgetId, key, value)
    }
  }

  readonly property BarWidget widgetItem: widget.item as BarWidget

  implicitWidth: widgetItem ? widgetItem.implicitWidth : 0
  implicitHeight: Style.barHeight
  visible: widgetItem !== null && !widgetItem.hidden

  property bool warned: false
  onEntryChanged: Qt.callLater(host.load)
  Component.onCompleted: Qt.callLater(host.load)

  // The widget is created with its real mode, screen, settings and shell
  // (initial properties), so its own Component.onCompleted already sees
  // them; the bindings follow in onLoaded. An unknown id warns here, once
  // the host is complete: entry starts out null, so its change handler
  // never runs for an id the index lacks.
  function load() {
    if (!host.entry) {
      widget.source = ""
      if (host.widgetId !== "" && !host.warned && Object.keys(WidgetIndex.widgets).length > 0) {
        console.warn("subcult shell: unknown widget", host.widgetId)
        host.warned = true
      }
      return
    }
    widget.setSource(Qt.resolvedUrl("widgets/" + host.entry.dir + "/Widget.qml"),
      { mode: host.mode, screen: host.screen, settings: host.settings, shell: host.shellServices })
  }

  Loader {
    id: widget
    anchors.fill: parent
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
      w.openPanel.connect(() => Panels.toggle(host))
    }
  }
}
