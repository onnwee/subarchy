import QtQuick
import QtTest
import "../SettingsModel.js" as Model

TestCase {
  name: "Settings"

  readonly property string schemaText: '{"schema": 1, "settings": [' +
    '{"id": "bar.minimal", "group": "Bar layout", "label": "Minimal bars", "kind": "widgets", "file": "shell/bar.json", "path": ["layout", "minimal"]},' +
    '{"id": "font.ui", "group": "Fonts", "label": "Interface", "kind": "font", "role": "sans-serif", "flags": ["--ui"]},' +
    '{"id": "cursor.size", "group": "Cursor", "label": "Size", "kind": "choice", "choices": [24, 32, 48], "file": "cursor.json", "path": ["size"], "default": 24, "after": ["subcult", "cursor", "apply"]},' +
    '{"id": "cursor.role", "group": "Cursor", "label": "Colour", "kind": "choice", "choices": ["lavender", "green"], "file": "cursor.json", "path": ["role"], "default": "lavender", "after": ["subcult", "cursor", "apply"]},' +
    '{"id": "idle.lock", "group": "Idle", "label": "Lock", "kind": "number", "min": 0, "max": 240, "file": "idle.json", "path": ["lockAfterMinutes"], "default": 7},' +
    '{"id": "broken", "kind": "number"}, null]}'
  readonly property var settings: Model.schema(schemaText)
  readonly property var bar: ({ layout: { minimal: ["subcult.workspaces", "subcult.display"] } })
  readonly property var files: ({ "cursor.json": '{"role": "green", "size": 24}' })
  readonly property var fontMap: Model.fonts("monospace   (default)  resolves to JetBrainsMono Nerd Font\nsans-serif  Inter\nserif       Lora  resolves to Lora Variable  mismatch: is it installed?\n")
  readonly property var cur: Model.current(settings, bar, files, fontMap)

  function test_schema() {
    compare(settings.map(s => s.id), ["bar.minimal", "font.ui", "cursor.size", "cursor.role", "idle.lock"], "a setting without a file is dropped")
    compare(Model.groups(settings), ["Bar layout", "Fonts", "Cursor", "Idle"])
    compare(Model.schema("nope"), [])
  }

  function test_fontsAndCurrent() {
    compare(fontMap["monospace"], "JetBrainsMono Nerd Font")
    compare(fontMap["sans-serif"], "Inter")
    compare(fontMap["serif"], "Lora Variable")
    compare(cur["bar.minimal"], ["subcult.workspaces", "subcult.display"], "bar layout from the merged config")
    compare(cur["font.ui"], "Inter")
    compare(cur["cursor.size"], 24)
    compare(cur["cursor.role"], "green", "from the user's file")
    compare(cur["idle.lock"], 7, "the schema default when the file is absent")
  }

  function test_coerce() {
    compare(Model.coerce(settings[0], "subcult.workspaces, subcult.clock", ["subcult.workspaces", "subcult.clock"]).value, ["subcult.workspaces", "subcult.clock"])
    compare(Model.coerce(settings[0], "subcult.nope", ["subcult.workspaces"]).error, "unknown widget subcult.nope")
    compare(Model.coerce(settings[0], "", []).value, [], "an empty list is allowed")
    compare(Model.coerce(settings[2], "32").value, 32)
    compare(Model.coerce(settings[2], "33").value, null)
    compare(Model.coerce(settings[3], "green").value, "green")
    compare(Model.coerce(settings[4], "5").value, 5)
    compare(Model.coerce(settings[4], "500").error, "between 0 and 240")
    compare(Model.coerce(settings[4], "x").error, "a whole number")
    compare(Model.coerce(settings[1], "  ").value, null)
    compare(Model.coerce(settings[1], "Inter").value, "Inter")
  }

  function test_previewAndPlan() {
    const pending = { "bar.minimal": ["subcult.workspaces"], "cursor.size": 32, "cursor.role": "lavender", "idle.lock": 5, "font.ui": "Inter" }
    const lines = Model.preview(settings, pending, cur)
    compare(lines.length, 4, "an unchanged value previews nothing")
    verify(lines[0].indexOf("Minimal bars: subcult.workspaces subcult.display → subcult.workspaces") === 0)
    verify(lines[0].indexOf("writes ~/.config/subcult/shell/bar.json") > 0)
    verify(lines[1].indexOf("then runs subcult cursor apply") > 0)
    const p = Model.plan(settings, pending, cur, files)
    compare(p.writes.map(w => w.file), ["shell/bar.json", "cursor.json", "idle.json"])
    compare(JSON.parse(p.writes[0].text), { layout: { minimal: ["subcult.workspaces"] } }, "only the changed key lands in the user's file")
    compare(JSON.parse(p.writes[1].text), { role: "lavender", size: 32 }, "both cursor keys, one file")
    compare(JSON.parse(p.writes[2].text), { lockAfterMinutes: 5 })
    compare(p.commands, [["subcult", "cursor", "apply"]], "cursor apply runs once after two cursor changes")
    compare(p.undo, { "bar.minimal": ["subcult.workspaces", "subcult.display"], "cursor.size": 24, "cursor.role": "green", "idle.lock": 7 })
    const f = Model.plan(settings, { "font.ui": "Iosevka Aile" }, cur, files)
    compare(f.writes, [])
    compare(f.commands, [["subcult", "font", "set", "Iosevka Aile", "--ui"]])
    compare(f.undo, { "font.ui": "Inter" })
  }

  function test_withValue() {
    compare(Model.withValue({ a: 1 }, ["b", "c"], 2), { a: 1, b: { c: 2 } })
    compare(Model.withValue("junk", ["x"], 1), { x: 1 })
    compare(Model.valueAt({ a: { b: 0 } }, ["a", "b"], 9), 0)
    compare(Model.valueAt({ a: 1 }, ["a", "b"], 9), 9)
  }
}
