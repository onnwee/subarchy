import QtQuick
import QtTest

import "../Commons/PowerModel.js" as PowerModel
import "../Commons/ConfigModel.js" as ConfigModel
import "../Commons/LayoutModel.js" as LayoutModel
import "../Commons/ThemeModel.js" as ThemeModel
import "../Commons/ManifestModel.js" as ManifestModel

TestCase {
  name: "Models"

  readonly property var weather: ({
    id: "subcult.weather", api: 0, kind: "bar-widget",
    cost: { timers: [{ name: "current", ac: 900, battery: 1800 }], network: ["api.open-meteo.com"] }
  })

  function test_intervalAc() {
    compare(PowerModel.intervalMs(weather, "current", false), 900000)
  }

  function test_intervalBattery() {
    compare(PowerModel.intervalMs(weather, "current", true), 1800000)
  }

  function test_intervalMissing() {
    let threw = false
    try { PowerModel.intervalMs(weather, "forecast", false) } catch (e) { threw = String(e).indexOf("no timer forecast") >= 0 }
    verify(threw, "a timer the manifest lacks must throw")
  }

  function test_mergeNested() {
    const merged = ConfigModel.merge(
      { layout: { left: ["a"], right: ["b"] }, primary: "", widgets: { x: { n: 1 } } },
      { layout: { left: ["c", "d"] }, widgets: { x: { m: 2 } } })
    compare(merged.layout.left, ["c", "d"])
    compare(merged.layout.right, ["b"])
    compare(merged.primary, "")
    compare(merged.widgets.x.n, 1)
    compare(merged.widgets.x.m, 2)
  }

  function test_mergeNonObjectUser() {
    const defaults = { a: 1 }
    const merged = ConfigModel.merge(defaults, "oops")
    compare(merged.a, 1)
    merged.a = 2
    compare(defaults.a, 1, "merge must not hand back the defaults object itself")
  }

  function test_parseBadJson() {
    const r = ConfigModel.parse("{ not json", { a: 1 })
    compare(r.config.a, 1)
    verify(r.warning.length > 0, "a parse failure must carry a warning")
  }

  function test_parseGoodJson() {
    const r = ConfigModel.parse('{"a": 2}', { a: 1, b: 3 })
    compare(r.config.a, 2)
    compare(r.config.b, 3)
    compare(r.warning, "")
  }

  function test_withWidgetSettingIsolated() {
    const user = { primary: "DP-3", widgets: { "subcult.clock": { format: "x" }, "subcult.other": { k: 1 } } }
    const next = ConfigModel.withWidgetSetting(user, "subcult.clock", "zone", "UTC")
    compare(next.widgets["subcult.clock"].zone, "UTC")
    compare(next.widgets["subcult.clock"].format, "x")
    compare(next.widgets["subcult.other"].k, 1)
    compare(next.primary, "DP-3")
    verify(user.widgets["subcult.clock"].zone === undefined, "the input must not change")
    const fresh = ConfigModel.withWidgetSetting({}, "subcult.clock", "zone", "UTC")
    compare(fresh.widgets["subcult.clock"].zone, "UTC")
  }

  function test_modeFor() {
    compare(LayoutModel.modeFor("eDP-1", { primary: "", full: [] }), "full")
    compare(LayoutModel.modeFor("DP-3", { primary: "", full: [] }), "minimal")
    compare(LayoutModel.modeFor("DP-3", { primary: "DP-3", full: [] }), "full")
    compare(LayoutModel.modeFor("HDMI-A-1", { primary: "", full: ["HDMI-A-1"] }), "full")
    compare(LayoutModel.modeFor("DP-3", {}), "minimal")
  }

  function test_widgetsFull() {
    const layout = { left: ["a", "b"], center: ["c"], right: ["d"], minimal: ["b"] }
    const w = LayoutModel.widgetsFor(layout, "full")
    compare(w.left, ["a", "b"])
    compare(w.center, ["c"])
    compare(w.right, ["d"])
  }

  function test_widgetsMinimal() {
    const layout = { left: ["a", "b"], center: ["c"], right: ["d", "e"], minimal: ["b", "e"] }
    const w = LayoutModel.widgetsFor(layout, "minimal")
    compare(w.left, ["b"])
    compare(w.center, [])
    compare(w.right, ["e"])
  }

  readonly property var fallback: ({
    base: "#100B19", mantle: "#0B0812", crust: "#06040A", surface0: "#1F1830", text: "#F0ECE4",
    subtext0: "#9A92A8", overlay0: "#5E5570", green: "#00FF88", mauve: "#8F4BC8",
    selection_bg: "#3B2470", yellow: "#F6D447", red: "#D52032"
  })

  function test_tokensMapping() {
    const t = ThemeModel.tokens(fallback, fallback)
    compare(t.base, "#100B19")
    compare(t.surface, "#1F1830")
    compare(t.text, "#F0ECE4")
    compare(t.subtext, "#9A92A8")
    compare(t.muted, "#5E5570")
    compare(t.accent, "#00FF88")
    compare(t.border, "#8F4BC8")
    compare(t.borderInactive, "#1F1830")
    compare(t.selection, "#3B2470")
    compare(t.warning, "#F6D447")
    compare(t.error, "#D52032")
  }

  function test_tokensFallback() {
    const broken = Object.assign({}, fallback, { base: "red", text: "#12345" })
    delete broken.mauve
    const t = ThemeModel.tokens(broken, fallback)
    compare(t.base, "#100B19")
    compare(t.text, "#F0ECE4")
    compare(t.border, "#8F4BC8")
    compare(ThemeModel.tokens(null, fallback).accent, "#00FF88")
  }

  function test_validateGood() {
    compare(ManifestModel.validate(weather, 0), [])
    compare(ManifestModel.validate({ id: "subcult.clock", api: 0, kind: "bar-widget" }, 0), [])
  }

  function test_validateErrors_data() {
    return [
      { tag: "api", m: { id: "subcult.a", api: 1, kind: "bar-widget" } },
      { tag: "kind", m: { id: "subcult.a", api: 0, kind: "panel" } },
      { tag: "id", m: { id: "omarchy.a", api: 0, kind: "bar-widget" } },
      { tag: "timer", m: { id: "subcult.a", api: 0, kind: "service", cost: { timers: [{ name: "t", ac: 60 }] } } },
      { tag: "host", m: { id: "subcult.a", api: 0, kind: "service", cost: { network: ["http://x/"] } } },
      { tag: "missing", m: null }
    ]
  }

  function test_validateErrors(data) {
    verify(ManifestModel.validate(data.m, 0).length > 0, data.tag + " must be rejected")
  }
}
