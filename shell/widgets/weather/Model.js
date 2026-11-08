.pragma library
// Weather (shell plan 2): current conditions from Open-Meteo, read directly
// and often; the forecast, sun, moon and tides from `linecast --json`, read
// rarely. Nothing is fetched until the user sets a location, which is
// "lat,lon" in the widget's settings with a name beside it.

const MARK = "---subcult---"
const ALMANAC = ["weather", "sunshine", "moon", "tides"]

// { lat, lon } from "44.98,-93.27", or null.
function location(settings) {
  const m = /^\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$/.exec(String((settings && settings.location) || ""))
  if (!m)
    return null
  const lat = Number(m[1]), lon = Number(m[2])
  if (!(lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180))
    return null
  return { lat: lat, lon: lon }
}

function imperial(settings) {
  return String((settings && settings.units) || "") === "imperial"
}

function openMeteoUrl(loc, imp) {
  return "https://api.open-meteo.com/v1/forecast?latitude=" + loc.lat + "&longitude=" + loc.lon
    + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&timezone=auto"
    + (imp ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "")
}

function currentCommand(loc, imp) {
  return ["curl", "-sf", "--max-time", "15", openMeteoUrl(loc, imp)]
}

// One run of linecast per almanac part, each a JSON document, separated.
function almanacCommand(loc, imp) {
  const script = 'for c in ' + ALMANAC.join(" ") + '; do linecast "$c" --json --location "$1" "$2" 2>/dev/null || echo null; printf \'\\n' + MARK + '\\n\'; done'
  return ["sh", "-c", script, "sh", loc.lat + "," + loc.lon, imp ? "--imperial" : "--metric"]
}

function searchCommand(query) {
  return ["linecast", "weather", "--search", String(query)]
}

// Open-Meteo's answer -> { temp, feels, humidity, code, wind, isDay, tempUnit, windUnit }, or null.
function parseCurrent(text) {
  try {
    const d = JSON.parse(text)
    const c = d && d.current
    if (!c || typeof c.temperature_2m !== "number")
      return null
    const u = d.current_units || {}
    return {
      temp: c.temperature_2m, feels: Number(c.apparent_temperature), humidity: Number(c.relative_humidity_2m),
      code: Number(c.weather_code), wind: Number(c.wind_speed_10m), isDay: c.is_day !== 0,
      tempUnit: String(u.temperature_2m || "°C"), windUnit: String(u.wind_speed_10m || "km/h"), time: String(c.time || "")
    }
  } catch (e) {
    return null
  }
}

// linecast's four documents -> { forecast, sun, moon, tides }; a part that
// failed is null. Null when the text is not the four parts.
function parseAlmanac(text) {
  const parts = String(text || "").split(MARK)
  if (parts.length !== ALMANAC.length + 1)
    return null
  const out = {}
  for (let i = 0; i < ALMANAC.length; i++) {
    let d = null
    try {
      d = JSON.parse(parts[i])
    } catch (e) {
    }
    out[ALMANAC[i]] = d && typeof d === "object" && d.schema === 1 ? d : null
  }
  return { forecast: out.weather, sun: out.sunshine, moon: out.moon, tides: out.tides }
}

// `linecast weather --search` lines: "  44.9800,-93.2638  Minneapolis, Minnesota, United States".
function parseSearch(text) {
  const out = []
  for (const line of String(text || "").split("\n")) {
    const m = /^\s*(-?\d+\.\d+),(-?\d+\.\d+)\s+(.+?)\s*$/.exec(line)
    if (m)
      out.push({ location: m[1] + "," + m[2], name: m[3] })
  }
  return out
}

// WMO weather codes, as Open-Meteo reports them.
function condition(code) {
  const c = Number(code)
  if (c === 0) return "Clear"
  if (c === 1) return "Mainly clear"
  if (c === 2) return "Partly cloudy"
  if (c === 3) return "Overcast"
  if (c === 45 || c === 48) return "Fog"
  if (c >= 51 && c <= 57) return c >= 56 ? "Freezing drizzle" : "Drizzle"
  if (c >= 61 && c <= 67) return c >= 66 ? "Freezing rain" : "Rain"
  if (c >= 71 && c <= 77) return "Snow"
  if (c >= 80 && c <= 82) return "Showers"
  if (c === 85 || c === 86) return "Snow showers"
  if (c === 95) return "Thunderstorm"
  if (c === 96 || c === 99) return "Thunderstorm with hail"
  return ""
}

// A Nerd Font weather glyph for a code, by day or night.
function glyph(code, isDay) {
  const c = Number(code)
  if (c === 0 || c === 1) return isDay === false ? "\u{F0594}" : "\u{F0599}" // night, sunny
  if (c === 2) return "\u{F0595}" // partly cloudy
  if (c === 3) return "\u{F0590}" // cloudy
  if (c === 45 || c === 48) return "\u{F0591}" // fog
  if (c >= 51 && c <= 57) return "\u{F0597}" // rainy
  if (c >= 61 && c <= 67) return c >= 65 ? "\u{F0596}" : "\u{F0597}" // pouring, rainy
  if (c >= 71 && c <= 77) return "\u{F0598}" // snowy
  if (c >= 80 && c <= 82) return "\u{F0596}" // pouring
  if (c === 85 || c === 86) return "\u{F0598}" // snowy
  if (c === 95) return "\u{F0593}" // lightning
  if (c === 96 || c === 99) return "\u{F0592}" // hail
  return "\u{F0590}"
}

function degrees(t) {
  return isFinite(Number(t)) ? Math.round(Number(t)) + "°" : "–"
}

// The bar: "12°", or "" without a reading.
function label(current) {
  return current ? degrees(current.temp) : ""
}

function tooltip(current, name) {
  if (!current)
    return name ? name + ": no reading yet" : "Set a location in the weather panel"
  return (name ? name + ": " : "") + degrees(current.temp) + " " + condition(current.code).toLowerCase()
    + ", feels " + degrees(current.feels) + ", wind " + Math.round(current.wind) + " " + current.windUnit
}

// "Mon", or "Today" for the first day.
function dayName(iso, index) {
  if (index === 0)
    return "Today"
  const d = new Date(iso + "T12:00:00")
  return isNaN(d.getTime()) ? String(iso) : Qt.formatDate(d, "ddd")
}

// "16:36" from "2026-11-08T16:36".
function clock(iso) {
  const m = /T(\d{2}:\d{2})/.exec(String(iso || ""))
  return m ? m[1] : ""
}

// "9h 50m" from seconds.
function duration(seconds) {
  const s = Number(seconds)
  if (!isFinite(s))
    return ""
  return Math.floor(s / 3600) + "h " + Math.round((s % 3600) / 60) + "m"
}

// Whether a fetch made at `at` (epoch ms) is older than `maxAgeMs` now.
function stale(at, maxAgeMs, now) {
  return !at || now - at > maxAgeMs
}

// The next tide events from now, up to n.
function nextTides(tides, now, n) {
  if (!tides || !Array.isArray(tides.events))
    return []
  return tides.events.filter(e => {
    const t = new Date(e.time)
    return !isNaN(t.getTime()) && t.getTime() >= now.getTime() - 60000
  }).slice(0, n)
}
