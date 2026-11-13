import QtQuick
import QtTest

import "../Commons/PowerModel.js" as PowerModel
import "../Commons/ConfigModel.js" as ConfigModel
import "../Commons/LayoutModel.js" as LayoutModel
import "../Commons/ThemeModel.js" as ThemeModel
import "../Commons/ManifestModel.js" as ManifestModel
import "../Commons/WorkspacesModel.js" as WorkspacesModel

TestCase {
  name: "Models"

  function test_combinedBatteryMigration() {
    const old = {primary: "DP-3", layout: {
      left: ["subcult.clock"], right: ["subcult.battery", "subcult.audio", "subcult.dell-power"],
      minimal: ["subcult.dell-power", "subcult.battery"]}, widgets: {"subcult.clock": {zone: "UTC"}}}
    const next = ConfigModel.normalize(old)
    compare(next.layout.right, ["subcult.battery", "subcult.audio"])
    compare(next.layout.minimal, ["subcult.battery"])
    compare(next.primary, "DP-3")
    compare(next.widgets, old.widgets)
    compare(old.layout.right.length, 3, "normalizing must not write the user file")
    compare(ConfigModel.normalize(next), next, "normalizing is idempotent")
    compare(ConfigModel.normalize({layout: {left: ["subcult.dell-power"], right: ["subcult.battery"]}}).layout,
      {left: [], right: ["subcult.battery"]}, "keep the owner's battery position")
    compare(ConfigModel.normalize({layout: {left: ["subcult.dell-power"]}}).layout.left, ["subcult.battery"])
  }

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

  function test_parseWrongTypes() {
    const defaults = { primary: "", layout: { left: ["a"], right: ["b"] }, widgets: {} }
    const r = ConfigModel.parse('{"primary": "DP-1", "layout": {"left": "c", "right": ["d", 3]}, "widgets": []}', defaults)
    compare(r.config.primary, "DP-1", "a good value next to bad ones applies")
    compare(r.config.layout.left, ["a"], "a string where a list belongs keeps the default")
    compare(r.config.layout.right, ["b"], "a list with a number keeps the default")
    compare(r.config.widgets, {})
    verify(r.warning.indexOf("layout.left") >= 0 && r.warning.indexOf("layout.right") >= 0 && r.warning.indexOf("widgets") >= 0, r.warning)
    const whole = ConfigModel.parse('{"layout": ["a"]}', defaults)
    compare(whole.config.layout, defaults.layout)
    verify(whole.warning.indexOf("layout is a list, not an object") >= 0, whole.warning)
    compare(ConfigModel.parse('{"layout": {"left": []}, "extra": 1}', defaults).warning, "", "an empty list and unknown keys are fine")
    const machine = ConfigModel.machine(defaults, '{"layout": {"right": "x"}}')
    compare(machine.config.layout.right, ["b"])
    verify(machine.warning.indexOf("layout.right") >= 0, machine.warning)
  }

  function test_machineLayerEnables() {
    const defaults = { layout: { left: ["a"], right: ["b"] }, widgets: {} }
    const r = ConfigModel.machine(defaults, '{"#": "# Subarchy hardware fix dell-power", "enable": ["subcult.dell-power", "b"], "widgets": {"x": {"n": 1}}}')
    compare(r.warning, "")
    compare(r.config.layout.right, ["b", "subcult.dell-power"], "enabled once, b was already there")
    compare(r.config.layout.left, ["a"])
    compare(r.config.widgets.x.n, 1)
    verify(r.config.enable === undefined && r.config["#"] === undefined, "the layer's own keys do not reach the config")
    compare(ConfigModel.machine(defaults, "").config.layout.right, ["b"])
    const bad = ConfigModel.machine(defaults, "{ nope")
    compare(bad.config.layout.right, ["b"])
    verify(bad.warning.length > 0)
    const user = ConfigModel.parse('{"layout": {"right": ["c"]}}', r.config)
    compare(user.config.layout.right, ["c"], "the user's layout still replaces")
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

  function test_modeForWithoutPrimaryOrLaptop() {
    // A desktop with no laptop panel and no primary set: the first output
    // gets the full bar, the rest minimal.
    compare(LayoutModel.modeFor("DP-1", { primary: "", full: [] }, ["DP-1", "HDMI-A-1"]), "full")
    compare(LayoutModel.modeFor("HDMI-A-1", { primary: "", full: [] }, ["DP-1", "HDMI-A-1"]), "minimal")
    // With a laptop panel present, the externals stay minimal.
    compare(LayoutModel.modeFor("DP-1", { primary: "", full: [] }, ["eDP-1", "DP-1"]), "minimal")
    // A primary that is not connected falls back the same way.
    compare(LayoutModel.modeFor("DP-1", { primary: "DP-9", full: [] }, ["DP-1"]), "full")
  }

  function test_modeForDescription() {
    // sputnik's dock: the LG moves between connectors, so the config names
    // the monitor, not the connector. Outputs carry their description.
    const outs = [{ name: "DP-3", description: "LG Electronics LG ULTRAGEAR 0x0001" },
                  { name: "DP-2", description: "ONN 100002487 0x0002" }]
    compare(LayoutModel.modeFor(outs[0], { primary: "LG ULTRAGEAR", full: [] }, outs), "full")
    compare(LayoutModel.modeFor(outs[1], { primary: "LG ULTRAGEAR", full: [] }, outs), "minimal")
    compare(LayoutModel.modeFor(outs[1], { primary: "", full: ["onn 100002487"] }, outs), "full", "case does not matter")
    compare(LayoutModel.modeFor(outs[0], { primary: "DP-3", full: [] }, outs), "full", "connector names still work")
    compare(LayoutModel.modeFor(outs[1], { primary: "LG ULTRAGEAR", full: [] }, [outs[1]]), "full",
            "with the named primary unplugged, the first output is Full")
  }

  function test_fallbackIgnored() {
    verify(LayoutModel.isReal("DP-3"))
    verify(!LayoutModel.isReal("FALLBACK"))
    verify(!LayoutModel.isReal(""))
    verify(!LayoutModel.isReal(undefined))
    const outs = [{ name: "FALLBACK", description: "" }, { name: "DP-1", description: "X" }]
    compare(LayoutModel.modeFor(outs[1], { primary: "", full: [] }, outs), "full", "FALLBACK is not the first output")
  }

  function test_describe() {
    compare(LayoutModel.describe({ name: "DP-3", model: "LG ULTRAGEAR", serialNumber: "0x1" },
                                 [{ name: "DP-3", description: "LG Electronics LG ULTRAGEAR 0x1" }]),
            "LG Electronics LG ULTRAGEAR 0x1", "Hyprland's description when it has the monitor")
    compare(LayoutModel.describe({ name: "DP-3", model: "LG ULTRAGEAR", serialNumber: "0x1" }, []), "LG ULTRAGEAR 0x1")
    compare(LayoutModel.describe({ name: "HEADLESS-1", model: "", serialNumber: "" }, null), "")
  }

  function test_pickScreenKeepsCurrent() {
    compare(LayoutModel.pickScreen(["DP-1", "DP-2"], "DP-1", "DP-2"), "DP-2", "an open overlay stays where it is")
    compare(LayoutModel.pickScreen(["DP-1", "DP-2"], "", "DP-2"), "DP-2")
  }

  function test_pickScreenFallsBack() {
    compare(LayoutModel.pickScreen(["DP-1", "DP-2"], "DP-2", ""), "DP-2", "opening: the focused output")
    compare(LayoutModel.pickScreen(["DP-1", "DP-2"], "DP-2", "DP-9"), "DP-2", "its output went: the focused one")
    compare(LayoutModel.pickScreen(["DP-1", "DP-2"], "DP-9", "DP-9"), "DP-1", "neither exists: the first")
    compare(LayoutModel.pickScreen(["DP-1"], "FALLBACK", ""), "DP-1", "FALLBACK is never chosen")
    compare(LayoutModel.pickScreen([], "DP-1", "DP-1"), "", "no outputs: none")
  }

  function test_workspaceNames() {
    const sys = JSON.stringify({ workspaces: [{ id: 1, name: "Archive", short: "arc" }, { id: 2, name: "Door" }] })
    const user = JSON.stringify({ workspaces: [{ id: 2, name: "Door list", short: "DOR" }, { id: 3, name: "Workbench · Development" },
      { id: 11, name: "out of range" }, { id: "x", name: "bad id" }, { id: 4, name: "ctl\u0007chars\u001b", short: "toolongtoken" }] })
    const names = WorkspacesModel.parse(sys, user)
    compare(Object.keys(names).sort(), ["1", "2", "3", "4"])
    compare(names[1], { name: "Archive", short: "ARC" }, "tokens are upper case")
    compare(names[2].short, "DOR", "the user's entry replaces the system's")
    compare(names[4], { name: "ctlchars", short: "TOOL" }, "control characters dropped, token cut to 4")
    compare(WorkspacesModel.parse("{broken", ""), {})
  }

  function test_workspaceLabels() {
    const names = WorkspacesModel.parse("", JSON.stringify({ workspaces: [{ id: 1, short: "ARC" }, { id: 3, name: "Workbench · Dev" }] }))
    compare(WorkspacesModel.label(names, 1), "ARC")
    compare(WorkspacesModel.label(names, 3), "WOR", "the first three letters of the name")
    compare(WorkspacesModel.label(names, 5), "5")
    compare(WorkspacesModel.label(names, 10), "0")
    compare(WorkspacesModel.title(names, 3), "3 · Workbench · Dev")
    compare(WorkspacesModel.title(names, 1), "Workspace 1", "a token alone has no name")
    compare(WorkspacesModel.title(names, 10), "Workspace 0")
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
      { tag: "string seconds", m: { id: "subcult.a", api: 0, kind: "service", cost: { timers: [{ name: "t", ac: "60", battery: 60 }] } } },
      { tag: "id in a list", m: { id: ["subcult.a"], api: 0, kind: "service" } },
      { tag: "cost not an object", m: { id: "subcult.a", api: 0, kind: "service", cost: "cheap" } },
      { tag: "missing", m: null }
    ]
  }

  function test_validateErrors(data) {
    verify(ManifestModel.validate(data.m, 0).length > 0, data.tag + " must be rejected")
  }
}
