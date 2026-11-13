import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs
import "../../Commons/HyprDispatch.js" as Dispatch

// Workspaces 1–0 for this output, as on sputnik's bar: the shown one as a
// filled square, occupied ones in text colour, empty ones muted. Named
// workspaces (Workspaces) show their compact token instead of the number,
// the shown one in the accent colour; the full name is the tooltip. Click
// to go there. Driven by Hyprland's events; nothing polls.
BarWidget {
  id: root

  readonly property string output: screen ? screen.name : ""
  readonly property var slots: Model.slots(Hyprland.workspaces.values.map(w => ({
    id: w.id,
    monitor: w.monitor ? w.monitor.name : "",
    windows: w.toplevels ? w.toplevels.values.length : 0,
    active: w.active
  })), output, 10)

  implicitWidth: row.implicitWidth

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Repeater {
      model: root.slots
      delegate: Item {
        id: slot
        required property var modelData
        readonly property bool named: Workspaces.names[slot.modelData.id] !== undefined
        readonly property string label: Workspaces.label(slot.modelData.id)
        readonly property string title: Workspaces.title(slot.modelData.id)
        width: Math.max(16, text.implicitWidth + 6)
        height: Style.barHeight

        Text {
          id: text
          anchors.centerIn: parent
          text: slot.modelData.active && !slot.named ? Glyphs.workspaceActive : slot.label
          color: slot.modelData.active ? (slot.named ? Theme.accent : Theme.text) : (slot.modelData.occupied ? Theme.text : Theme.muted)
          font.family: Style.fontFamily
          font.pixelSize: Style.fontSize
          font.bold: slot.named && slot.modelData.active
        }

        Tooltip {
          target: slot
          text: slot.title
          shown: area.containsMouse && slot.title !== ""
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            const ws = Hyprland.workspaces.values.find(w => w.id === slot.modelData.id)
            if (ws)
              ws.activate()
            else
              Hyprland.dispatch(Dispatch.workspace(slot.modelData.id))
          }
        }
      }
    }
  }
}
