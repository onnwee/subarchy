pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SettingsModel.js" as Model

// The settings panel (rice port, ADR 0048): every setting in
// default/shell/settings.json with its current value and a field for a new
// one. Pending changes are previewed with what they write or run; Apply
// writes the user override files under ~/.config/subcult (and runs
// `subcult font set` or `subcult cursor apply` where the schema says so);
// Undo puts back the values the last apply replaced, once. The shell
// (Config), Hyprland and the tools pick the files up through their own
// watches; nothing here polls. `subcult.settings` over IPC drives it for
// the tests while the panel is open.
PanelBase {
  id: panel

  readonly property string configDir: Quickshell.env("HOME") + "/.config/subcult/"
  readonly property string undoPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/settings-undo.json"
  property string schemaText: ""
  readonly property var items: Model.schema(schemaText)
  readonly property var widgetIds: Object.keys(WidgetIndex.widgets)
  property var fontMap: ({})
  readonly property var files: ({ "shell/bar.json": Config.userText, "cursor.json": cursorFile.text, "idle.json": idleFile.text, "motion.json": motionFile.text })
  readonly property var current: Model.current(items, Config.bar, files, fontMap)
  // id -> typed value waiting for Apply; id -> error text for bad input.
  property var pending: ({})
  property var errors: ({})
  readonly property var previewLines: Model.preview(items, pending, current)
  readonly property var undoRecord: Model.parseJSON(undoFile.text)
  readonly property bool canUndo: Object.keys(undoRecord.values || {}).length > 0
  property string status: ""

  implicitWidth: 460
  implicitHeight: column.implicitHeight

  function set(id, text) {
    const s = panel.items.find(x => x.id === id)
    if (!s)
      return false
    const r = Model.coerce(s, text, panel.widgetIds)
    const p = Object.assign({}, panel.pending)
    const e = Object.assign({}, panel.errors)
    if (r.value === null) {
      delete p[id]
      e[id] = r.error
    } else {
      p[id] = r.value
      delete e[id]
    }
    panel.pending = p
    panel.errors = e
    return r.value !== null
  }

  function fileFor(name) {
    return name === "shell/bar.json" ? barFile : name === "cursor.json" ? cursorFile : name === "idle.json" ? idleFile : name === "motion.json" ? motionFile : null
  }

  // Writes the plan; the record of the replaced values goes to the undo
  // file, replacing the previous record (one step).
  function applyValues(values) {
    const p = Model.plan(panel.items, values, panel.current, panel.files)
    if (p.writes.length === 0 && p.commands.length === 0) {
      panel.status = "Nothing to apply"
      return
    }
    for (const w of p.writes) {
      const f = panel.fileFor(w.file)
      if (f)
        f.setText(w.text)
    }
    undoFile.setText(JSON.stringify({ time: new Date().toISOString(), values: p.undo }) + "\n")
    // A command may still be running from the last Apply or Undo: these
    // wait behind it.
    runner.queue = runner.queue.concat(p.commands)
    if (!runner.running)
      runner.next()
    panel.pending = {}
    panel.errors = {}
    panel.status = "Applied " + Object.keys(p.undo).length + " change" + (Object.keys(p.undo).length === 1 ? "" : "s")
  }

  function apply() {
    panel.applyValues(panel.pending)
  }

  function undo() {
    if (!panel.canUndo)
      return
    panel.applyValues(panel.undoRecord.values)
    undoFile.setText("{}\n")
    panel.status = "Undone"
  }

  FileView {
    path: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/shell/settings.json"
    blockLoading: true
    printErrors: false
    onLoaded: panel.schemaText = text()
  }

  WatchedFile {
    id: barFile
    path: panel.configDir + "shell/bar.json"
  }
  WatchedFile {
    id: cursorFile
    path: panel.configDir + "cursor.json"
  }
  WatchedFile {
    id: idleFile
    path: panel.configDir + "idle.json"
  }
  WatchedFile {
    id: motionFile
    path: panel.configDir + "motion.json"
  }
  WatchedFile {
    id: undoFile
    path: panel.undoPath
  }

  // The current font roles, read when the panel opens and after a change.
  Process {
    id: fontQuery
    running: true
    command: ["subcult", "font", "current"]
    stdout: StdioCollector {
      onStreamFinished: panel.fontMap = Model.fonts(text)
    }
  }

  // The plan's commands, one after the other; fonts are read again after.
  Process {
    id: runner
    property var queue: []
    function next() {
      if (runner.queue.length === 0) {
        fontQuery.running = true
        return
      }
      runner.command = runner.queue[0]
      runner.queue = runner.queue.slice(1)
      runner.running = true
    }
    onExited: (code) => {
      if (code !== 0)
        panel.status = "A command failed (exit " + code + "): " + runner.command.join(" ")
      runner.next()
    }
  }

  IpcHandler {
    target: "subcult.settings"
    function set(id: string, text: string): bool { return panel.set(id, text) }
    function apply(): void { panel.apply() }
    function undo(): void { panel.undo() }
    function state(): string {
      return JSON.stringify({ current: panel.current, pending: panel.pending, errors: panel.errors, preview: panel.previewLines, canUndo: panel.canUndo, status: panel.status })
    }
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Text {
      text: "Settings"
      color: Theme.text
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize + 1
      font.bold: true
    }

    Repeater {
      model: Model.groups(panel.items)
      delegate: Column {
        id: group
        required property string modelData
        width: column.width
        spacing: 2
        Text {
          topPadding: 4
          text: group.modelData
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
          font.bold: true
        }
        Repeater {
          model: panel.items.filter(s => (s.group || "Other") === group.modelData)
          delegate: Item {
            id: row
            required property var modelData
            readonly property bool changed: row.modelData.id in panel.pending
            readonly property string error: panel.errors[row.modelData.id] || ""
            width: group.width
            height: 30

            Text {
              id: label
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 190
              text: row.modelData.label
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Theme.text
              font.family: Style.uiFontFamily
              font.pixelSize: Style.fontSize
            }
            Rectangle {
              anchors.left: label.right
              anchors.leftMargin: 8
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: 24
              color: Theme.base
              border.width: 1
              border.color: row.error !== "" ? Theme.error : row.changed ? Theme.accent : Theme.surface
              TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                selectionColor: Theme.selection
                font.family: Style.uiFontFamily
                font.pixelSize: Style.fontSize
                onTextEdited: panel.set(row.modelData.id, text)
                Text {
                  visible: field.text === ""
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.show(panel.current[row.modelData.id])
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  width: parent.width
                  color: Theme.muted
                  font: field.font
                }
                // A choice cycles with a click on the empty field.
                MouseArea {
                  anchors.fill: parent
                  enabled: row.modelData.kind === "choice" && field.text === ""
                  onClicked: {
                    const cs = row.modelData.choices || []
                    const now = String(row.changed ? panel.pending[row.modelData.id] : panel.current[row.modelData.id])
                    const i = cs.findIndex(c => String(c) === now)
                    field.text = String(cs[(i + 1) % cs.length])
                    panel.set(row.modelData.id, field.text)
                  }
                }
              }
            }
            Text {
              visible: row.error !== ""
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.bottom: parent.bottom
              text: row.error
              color: Theme.error
              font.family: Style.uiFontFamily
              font.pixelSize: Style.fontSize - 3
            }
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Theme.surface
    }

    Text {
      visible: panel.previewLines.length === 0
      width: parent.width
      text: panel.status !== "" ? panel.status : "Type a value to preview a change; a choice cycles on click."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 1
    }
    Repeater {
      model: panel.previewLines
      delegate: Text {
        required property string modelData
        width: column.width
        text: modelData
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
      }
    }

    Row {
      spacing: 8
      Rectangle {
        width: 90
        height: 28
        radius: 3
        color: panel.previewLines.length > 0 ? Theme.selection : Theme.base
        border.width: 1
        border.color: panel.previewLines.length > 0 ? Theme.accent : Theme.surface
        Text {
          anchors.centerIn: parent
          text: "Apply"
          color: panel.previewLines.length > 0 ? Theme.text : Theme.muted
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        MouseArea {
          anchors.fill: parent
          enabled: panel.previewLines.length > 0
          onClicked: panel.apply()
        }
      }
      Rectangle {
        width: 90
        height: 28
        radius: 3
        color: Theme.base
        border.width: 1
        border.color: panel.canUndo ? Theme.warning : Theme.surface
        Text {
          anchors.centerIn: parent
          text: "Undo last"
          color: panel.canUndo ? Theme.text : Theme.muted
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        MouseArea {
          anchors.fill: parent
          enabled: panel.canUndo
          onClicked: panel.undo()
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Writes only your files under ~/.config/subcult"
        color: Theme.muted
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 2
      }
    }
  }
}
