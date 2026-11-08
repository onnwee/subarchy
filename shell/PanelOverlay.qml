pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The click-out panel host (shell stage 2): one panel at a time, on the
// output of the bar whose widget opened it, under that widget. A
// transparent layer over the whole output, so a click outside the panel or
// Escape closes it. The panel's content exists only while it is open.
PanelWindow { // qmllint disable uncreatable-type
  id: overlay

  readonly property var host: Panels.host
  readonly property PanelBase panelItem: loader.item as PanelBase

  visible: host !== null
  screen: host ? host.screen : Quickshell.screens[0] || null
  WlrLayershell.namespace: "subcult-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"

  MouseArea {
    anchors.fill: parent
    onClicked: Panels.close()
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: Panels.close()

    Rectangle {
      id: frame
      x: Math.max(Style.spacing, Math.min(Panels.anchorX, overlay.width - width - Style.spacing))
      y: Style.barHeight + Style.spacing
      width: overlay.panelItem ? overlay.panelItem.implicitWidth + 2 * Style.spacing : 0
      height: overlay.panelItem ? overlay.panelItem.implicitHeight + 2 * Style.spacing : 0
      visible: overlay.panelItem !== null
      color: Theme.mantle
      border.width: 1
      border.color: Theme.border

      // Clicks inside the frame stay inside.
      MouseArea {
        anchors.fill: parent
      }

      Loader {
        id: loader
        x: Style.spacing
        y: Style.spacing
        active: overlay.host !== null && overlay.host.entry !== null && overlay.host.manifest.panel === true
        onActiveChanged: {
          if (active)
            setSource(Qt.resolvedUrl("widgets/" + overlay.host.entry.dir + "/Panel.qml"),
              { settings: overlay.host.settings, shell: overlay.host.shellServices })
        }
        onLoaded: {
          const p = item as PanelBase
          if (!p) {
            console.warn("subcult shell:", overlay.host.widgetId, "Panel.qml is not a PanelBase")
            return
          }
          p.settings = Qt.binding(() => overlay.host ? overlay.host.settings : ({}))
          p.shell = overlay.host.shellServices
          p.closePanel.connect(() => Panels.close())
        }
      }
    }
  }
}
