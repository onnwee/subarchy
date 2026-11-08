import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Agents"

  readonly property string fixture: JSON.stringify({
    scannedAt: "2026-11-08T15:00:00Z",
    agents: [
      { id: "claude", name: "Claude Code", found: true, today: { input: 1515, output: 300, total: 1815 }, week: { total: 4116 }, paceHour: 1210, sessions: 1, limits: [] },
      { id: "codex", name: "Codex", found: true, today: { total: 5700, output: 700 }, week: { total: 13400 }, paceHour: 2300, sessions: 1, plan: "pro",
        limits: [{ name: "primary", usedPercent: 54.2, windowMinutes: 300, resetsAt: "2026-11-08T17:10:00Z" }, { name: "secondary", usedPercent: 12, windowMinutes: 10080, resetsAt: "2026-11-12T00:00:00Z" }] },
      { id: "opencode", name: "OpenCode", found: false, today: { total: 0 }, week: { total: 0 }, limits: [] }
    ]
  })

  function test_parse() {
    verify(Model.parse(fixture) !== null)
    compare(Model.parse("nope"), null)
    compare(Model.parse('{"agents": 3}'), null)
  }

  function test_shownFollowsSettings() {
    const r = Model.parse(fixture)
    compare(Model.shown(r, ["claude", "codex", "opencode"]).map(a => a.id), ["claude", "codex"], "an agent without files is left out")
    compare(Model.shown(r, ["codex"]).map(a => a.id), ["codex"])
    compare(Model.shown(null, ["codex"]), [])
    compare(Model.shown(r, "codex"), [])
  }

  function test_label() {
    const r = Model.parse(fixture)
    compare(Model.barLabel(Model.shown(r, ["claude", "codex"])), "C 1.8k · X 54%", "tokens today without limits; the tightest limit with")
    compare(Model.label({ id: "other", name: "Other", today: { total: 12 }, limits: [] }), "O 12")
  }

  function test_tokens() {
    compare(Model.tokens(999), "999")
    compare(Model.tokens(1234), "1.2k")
    compare(Model.tokens(2345678), "2.3M")
    compare(Model.tokens(3456789012), "3.5G")
    compare(Model.tokens(undefined), "0")
  }

  function test_limitText() {
    const r = Model.parse(fixture)
    const codex = r.agents[1]
    const now = new Date("2026-11-08T15:00:00Z")
    compare(Model.resets(codex.limits[0], now), "resets in 2h 10m")
    verify(Model.resets(codex.limits[1], now).indexOf("resets ") === 0 && Model.resets(codex.limits[1], now).indexOf(":") > 0, "far resets show the day and time")
    compare(Model.resets({ resetsAt: "0001-01-01T00:00:00Z" }, now), "")
    compare(Model.resets({ resetsAt: "2026-11-08T14:00:00Z" }, now), "resets now")
    compare(Model.window(codex.limits[0]), "5 h")
    compare(Model.window(codex.limits[1]), "7 d")
    compare(Model.window({ windowMinutes: 30 }), "30 min")
    compare(Model.limit(codex).name, "primary")
    compare(Model.limit(r.agents[0]), null)
  }
}
