import QtQuick

// The v0 panel contract (ADR 0068): Panel.qml is a PanelBase, loaded only
// while its panel is open.
Item {
  property var settings: ({})
  property var shell: ({})

  signal closePanel()
}
