.pragma library
// Battery alerts (rice port: battery alerts with hysteresis). Low and
// critical fire once per crossing while on battery; each re-arms only
// after the level climbs back above its threshold plus the hysteresis, or
// after a charge. A crossing seen while charging never fires.

const LOW = 20
const CRITICAL = 10
const HYSTERESIS = 5

function initial() {
  return { lowArmed: true, criticalArmed: true }
}

// state: the alert state; reading: { percent, onBattery }.
// Returns { state, alerts } with alerts in ["critical", "low"] order.
function step(state, reading) {
  const s = Object.assign({}, state || initial())
  const alerts = []
  const p = Number(reading && reading.percent)
  const onBattery = !!(reading && reading.onBattery)
  if (!isFinite(p))
    return { state: s, alerts: alerts }
  if (!onBattery) {
    s.lowArmed = true
    s.criticalArmed = true
    return { state: s, alerts: alerts }
  }
  if (p > LOW + HYSTERESIS)
    s.lowArmed = true
  if (p > CRITICAL + HYSTERESIS)
    s.criticalArmed = true
  if (p <= CRITICAL && s.criticalArmed) {
    s.criticalArmed = false
    s.lowArmed = false
    alerts.push("critical")
  } else if (p <= LOW && s.lowArmed) {
    s.lowArmed = false
    alerts.push("low")
  }
  return { state: s, alerts: alerts }
}

// The notification for an alert: [urgency, summary, body].
function message(alert, percent) {
  if (alert === "critical")
    return ["critical", "Battery critical", "At " + percent + "%. Plug in now; the machine will suspend soon."]
  return ["normal", "Battery low", "At " + percent + "%. Plug in when you can."]
}
