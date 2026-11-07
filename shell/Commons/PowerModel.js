.pragma library
// Interval selection for widget timers (ADR 0068). Every repeating timer is
// declared in the widget's manifest with an AC and a battery value in
// seconds; widgets never hard-code an interval.

function intervalMs(manifest, timerName, onBattery) {
  const timers = (manifest && manifest.cost && manifest.cost.timers) || []
  for (let i = 0; i < timers.length; i++) {
    if (timers[i].name === timerName)
      return (onBattery ? timers[i].battery : timers[i].ac) * 1000
  }
  throw new Error("no timer " + timerName)
}
