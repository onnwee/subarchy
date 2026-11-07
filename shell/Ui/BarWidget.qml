import QtQuick

// The v0 widget contract (ADR 0068). Every widgets/<dir>/Widget.qml is a
// BarWidget; the host sets these properties and listens to openPanel.
Item {
  property string mode: "full" // "full" or "minimal"
  property var screen
  property var settings: ({})
  property var shell: ({}) // { theme, power, config, style, manifest }

  signal openPanel()

  implicitHeight: 26
}
