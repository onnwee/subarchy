import QtQuick
import qs.Commons

// The only timer a widget may use (ADR 0068): its interval is the
// manifest's AC or battery value for timerName and changes with the power
// source. It registers with Power, so the shell can report what runs.
Timer {
  id: timer

  required property BarWidget widget
  required property string timerName

  readonly property string widgetId: widget.shell && widget.shell.manifest ? widget.shell.manifest.id : ""

  interval: widget.shell && widget.shell.power ? widget.shell.power.interval(timerName) : 0

  Component.onCompleted: Power.register(timer)
  Component.onDestruction: Power.unregister(timer)
}
