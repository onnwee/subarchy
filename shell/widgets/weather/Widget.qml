import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model

// Weather in the bar (shell plan 2): a glyph for the conditions and the
// temperature. Current conditions refresh every 15 min on AC and 30 on
// battery (Open-Meteo); the forecast, sun, moon and tides (linecast) every
// 2 h on AC and 6 h on battery, and when the panel opens with old data.
// Nothing touches the network until the panel sets a location.
BarWidget {
  id: root

  readonly property var current: Weather.current
  readonly property string label: Model.label(current)
  readonly property string name: String(settings.name || "")

  implicitWidth: button.implicitWidth

  onSettingsChanged: Weather.configure(settings)
  Component.onCompleted: Weather.configure(settings)

  WidgetTimer {
    id: currentTimer
    widget: root
    timerName: "current"
    running: Weather.location !== null
    repeat: true
    onTriggered: Weather.refreshCurrent(currentTimer.interval / 2)
  }

  WidgetTimer {
    id: almanacTimer
    widget: root
    timerName: "almanac"
    running: Weather.location !== null
    repeat: true
    onTriggered: Weather.refreshAlmanac(almanacTimer.interval / 2)
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.current ? Model.glyph(root.current.code, root.current.isDay) : "\u{F0595}"
    label: root.mode === "full" ? root.label : ""
    color: root.current ? Theme.text : Theme.muted
    tooltip: Model.tooltip(root.current, root.name)
    onClicked: root.openPanel()
  }
}
