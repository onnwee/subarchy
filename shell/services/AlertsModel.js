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

// Thermal alerts (rice port, issue #98). The kernel reports each trip point
// crossed, up or down, through `subcult thermal watch`; the shell alerts on
// a hot or critical trip going up, once per excursion: the trip must come
// back down before the same zone's trip can fire again, and a zone keeps a
// cooldown between its alerts so a reading hopping around a trip fires once.
const HOT_COOLDOWN_MS = 20 * 60 * 1000
const CRITICAL_COOLDOWN_MS = 5 * 60 * 1000

function thermalInitial() {
  return { armed: {}, last: {} }
}

// One line of `subcult thermal watch`: the event, or null.
function parseThermal(line) {
  try {
    const e = JSON.parse(line)
    if (!e || typeof e !== "object" || !isFinite(Number(e.zone)) || typeof e.direction !== "string")
      return null
    return {
      zone: Number(e.zone), type: String(e.type || ""), kind: String(e.kind || ""),
      temp: Number(e.temp), tripTemp: Number(e.tripTemp), direction: e.direction
    }
  } catch (err) {
    return null
  }
}

// state: the thermal state; event: a parsed event; now: epoch ms.
// Returns { state, alert } with alert "hot", "critical" or null.
function thermalStep(state, event, now) {
  const s = { armed: Object.assign({}, (state || thermalInitial()).armed), last: Object.assign({}, (state || thermalInitial()).last) }
  if (!event || (event.kind !== "hot" && event.kind !== "critical"))
    return { state: s, alert: null }
  const key = event.zone + ":" + event.kind
  if (event.direction === "down") {
    s.armed[key] = true
    return { state: s, alert: null }
  }
  if (event.direction !== "up" || s.armed[key] === false)
    return { state: s, alert: null }
  s.armed[key] = false
  const cooldown = event.kind === "critical" ? CRITICAL_COOLDOWN_MS : HOT_COOLDOWN_MS
  if (s.last[key] !== undefined && now - s.last[key] < cooldown)
    return { state: s, alert: null }
  s.last[key] = now
  return { state: s, alert: event.kind }
}

function degrees(milli) {
  return isFinite(milli) ? Math.round(milli / 1000) + " °C" : "?"
}

// The notification for a thermal alert: [urgency, summary, body].
function thermalMessage(event) {
  const where = (event.type !== "" ? event.type : "zone " + event.zone) + " at " + degrees(event.temp)
    + (isFinite(event.tripTemp) && event.tripTemp > 0 ? ", past its " + event.kind + " trip at " + degrees(event.tripTemp) : "")
  if (event.kind === "critical")
    return ["critical", "Temperature critical", where + ". Save your work; the machine shuts down at this point to protect itself."]
  return ["normal", "Running hot", where + ". Ease the load or check the airflow."]
}
