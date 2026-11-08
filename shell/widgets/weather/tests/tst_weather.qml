import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Weather"

  function test_location() {
    compare(Model.location({ location: "44.98,-93.27" }), { lat: 44.98, lon: -93.27 })
    compare(Model.location({ location: " 41.88 , -87.63 " }), { lat: 41.88, lon: -87.63 })
    compare(Model.location({ location: "" }), null)
    compare(Model.location({ location: "Minneapolis" }), null)
    compare(Model.location({ location: "95,10" }), null, "latitude out of range")
    compare(Model.location({}), null)
  }

  function test_commands() {
    const loc = { lat: 44.98, lon: -93.27 }
    const c = Model.currentCommand(loc, false)
    compare(c[0], "curl")
    verify(c[4].indexOf("https://api.open-meteo.com/v1/forecast?latitude=44.98&longitude=-93.27") === 0)
    verify(c[4].indexOf("temperature_unit") < 0)
    verify(Model.currentCommand(loc, true)[4].indexOf("temperature_unit=fahrenheit") > 0)
    const a = Model.almanacCommand(loc, true)
    compare(a[0], "sh")
    compare(a[4], "44.98,-93.27")
    compare(a[5], "--imperial")
    compare(Model.almanacCommand(loc, false)[5], "--metric")
    verify(a[2].indexOf("weather sunshine moon tides") > 0)
    compare(Model.searchCommand("Minneapolis"), ["linecast", "weather", "--search", "Minneapolis"])
  }

  function test_parseCurrent() {
    const c = Model.parseCurrent('{"current_units":{"temperature_2m":"°F","wind_speed_10m":"mp/h"},"current":{"time":"2026-11-08T13:00","temperature_2m":57.2,"apparent_temperature":50.5,"relative_humidity_2m":56,"weather_code":2,"wind_speed_10m":11,"is_day":1}}')
    compare(c.temp, 57.2)
    compare(c.code, 2)
    compare(c.isDay, true)
    compare(c.tempUnit, "°F")
    compare(Model.parseCurrent('{"current":{"temperature_2m":"x"}}'), null)
    compare(Model.parseCurrent("nope"), null)
    compare(Model.parseCurrent('{"current":{"temperature_2m":5,"is_day":0}}').isDay, false)
  }

  function test_parseAlmanac() {
    const text = '{"schema":1,"daily":[{"date":"2026-11-08","high":59,"low":36}]}\n---subcult---\n{"schema":1,"sunrise":"2026-11-08T06:31"}\n---subcult---\nnull\n---subcult---\n{"schema":2}\n---subcult---\n'
    const a = Model.parseAlmanac(text)
    compare(a.forecast.daily[0].high, 59)
    compare(a.sun.sunrise, "2026-11-08T06:31")
    compare(a.moon, null, "a failed run is null")
    compare(a.tides, null, "an unknown schema is null")
    compare(Model.parseAlmanac("{}"), null)
  }

  function test_parseSearch() {
    const r = Model.parseSearch("  44.9800,-93.2638  Minneapolis, Minnesota, United States\n  39.1219,-97.7067  Minneapolis, Kansas, United States\nno match here\n")
    compare(r.length, 2)
    compare(r[0], { location: "44.9800,-93.2638", name: "Minneapolis, Minnesota, United States" })
    compare(Model.parseSearch(""), [])
  }

  function test_conditionsAndGlyphs() {
    compare(Model.condition(0), "Clear")
    compare(Model.condition(3), "Overcast")
    compare(Model.condition(65), "Rain")
    compare(Model.condition(66), "Freezing rain")
    compare(Model.condition(99), "Thunderstorm with hail")
    compare(Model.condition(42), "")
    compare(Model.glyph(0, true), "\u{F0599}")
    compare(Model.glyph(0, false), "\u{F0594}")
    compare(Model.glyph(95, true), "\u{F0593}")
    compare(Model.glyph(999, true), "\u{F0590}")
  }

  function test_labels() {
    const c = { temp: 12.4, feels: 10.1, code: 2, wind: 11.6, windUnit: "km/h" }
    compare(Model.label(c), "12°")
    compare(Model.label(null), "")
    compare(Model.tooltip(c, "Minneapolis"), "Minneapolis: 12° partly cloudy, feels 10°, wind 12 km/h")
    compare(Model.tooltip(null, ""), "Set a location in the weather panel")
    compare(Model.degrees("x"), "–")
    compare(Model.clock("2026-11-08T16:36"), "16:36")
    compare(Model.duration(35432), "9h 51m")
    compare(Model.dayName("2026-11-08", 0), "Today")
    verify(Model.dayName("2026-11-09", 1).length === 3)
  }

  function test_timerAndAlmanacData() {
    const manifest = { cost: { timers: [{ name: "current", ac: 600, battery: 1800 }] } }
    compare(Model.timerMs(manifest, "current", 900000), 600000)
    compare(Model.timerMs(manifest, "almanac", 7200000), 7200000, "an undeclared timer keeps the fallback")
    compare(Model.timerMs(null, "current", 900000), 900000)
    verify(Model.almanacHasData({ forecast: null, sun: { x: 1 }, moon: null, tides: null }))
    verify(!Model.almanacHasData({ forecast: null, sun: null, moon: null, tides: null }))
    verify(!Model.almanacHasData(null))
  }

  function test_staleAndTides() {
    verify(Model.stale(0, 1000, 5000))
    verify(Model.stale(1000, 1000, 5000))
    verify(!Model.stale(4500, 1000, 5000))
    const now = new Date("2026-11-08T12:00:00")
    const tides = { events: [{ kind: "low", time: "2026-11-08T05:00", height: 1 }, { kind: "high", time: "2026-11-08T17:12", height: 5 }, { kind: "low", time: "2026-11-09T00:07", height: -0.6 }] }
    compare(Model.nextTides(tides, now, 2).map(e => e.kind), ["high", "low"])
    compare(Model.nextTides(null, now, 2), [])
  }
}
