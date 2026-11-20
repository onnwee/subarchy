pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import "LauncherModel.js" as Model

// The launcher (ADR 0057), opened with Super+Space through a global
// shortcut. Typing searches the desktop entries, the subcult commands, the
// user's script commands and snippets; an empty query shows the favorites.
// Pinned favorites come first, then frecency from the history file. Math
// gets an inline qalc answer ("=" asks the calculator alone); "@" and a
// query with no match search the web; "." searches file names with fd
// while typing (no index); ":" searches emoji and symbols and copies the
// pick. A preview pane shows the selected file or symbol. The last row of a
// root search asks the default agent (`subcult app ask`); it says the text
// leaves the machine, and the answer shows in the preview pane. "$" (and
// Super+Ctrl+V) lists the clipboard history `subcult clipboard` keeps;
// Enter copies an entry back. Each alias
// the user names is also a global shortcut, subcult:alias.<name>, for
// Hyprland bindings.
// Quickshell keeps the app list and refreshes it when desktop entries
// change, but only in folders that existed when it first read them, so the
// user's applications folder is created first. The window is mapped only while
// open.
PanelWindow { // qmllint disable uncreatable-type
  id: launcher

  property bool open: false
  property string query: ""
  property int index: 0

  // A dangerous command waiting for Enter to confirm it.
  property var pending: null
  property var commands: []
  property var scripts: []
  // A script command asking for its arguments, and those typed so far.
  property var argFor: null
  property var argValues: []
  property var calcResult: ({ expr: "", answer: "" })
  property bool calcAgain: false
  // The file search's rows and the text they answer; fd runs on demand.
  property var fileResult: ({ text: "", rows: [] })
  property bool fdAgain: false
  // Emoji from unicode-emoji's emoji-test.txt, read the first time ":" is typed.
  property bool wantSymbols: false
  property var emojiItems: []
  property string systemSymbols: ""
  property string preview: ""
  property bool previewAgain: false
  // The default agent ({id, name}) from `subcult app ask --json`, read when
  // the launcher opens; null hides the Ask row. A question being asked and
  // its answer so far.
  property var agent: null
  property var asking: null
  // The clipboard history, read when "$" is typed and after a copy or clear.
  property var clips: []

  readonly property string systemDir: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/launcher/"
  readonly property string userDir: Quickshell.env("HOME") + "/.config/subcult/launcher/"
  readonly property string scriptDir: Quickshell.env("HOME") + "/.config/subcult/commands"
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
  readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/launcher/history.json"

  property var systemFavorites: []
  property string systemQuicklinks: ""
  property string systemSnippets: ""
  property bool entriesReady: false
  readonly property var favorites: Model.favorites(userFavorites.text) || launcher.systemFavorites
  readonly property var history: Model.parseHistory(historyFile.text)
  readonly property var apps: !launcher.entriesReady ? [] : DesktopEntries.applications.values
    .filter(e => !e.noDisplay)
    .map(e => ({ id: e.id, name: e.name, genericName: e.genericName, keywords: e.keywords, icon: e.icon }))
  readonly property var quicklinks: Model.quicklinks(launcher.systemQuicklinks, userQuicklinks.text)
  readonly property var snippets: Model.snippets(launcher.systemSnippets, userSnippets.text)
  readonly property var aliasNames: Model.aliases(aliasFile.text)
  readonly property var items: launcher.apps.concat(launcher.commands, launcher.scripts, launcher.snippets)
  readonly property var symbolItems: Model.symbols(launcher.systemSymbols).concat(launcher.emojiItems)
  readonly property var parsed: Model.parseQuery(launcher.query)
  readonly property string calcExpr: launcher.parsed.mode === "calc"
    || (launcher.parsed.mode === "root" && Model.looksLikeMath(launcher.parsed.text)) ? launcher.parsed.text : ""
  readonly property var results: launcher.open ? launcher.rows(launcher.query) : []
  readonly property var selected: launcher.results[launcher.index] || null
  readonly property bool previewing: launcher.selected !== null && ["file", "symbol", "ask", "clip", "snippet"].indexOf(launcher.selected.kind) >= 0
  readonly property bool home: launcher.query.trim() === "" && !launcher.argFor
  readonly property int columns: Math.max(1, Math.min(4, Math.floor(resultsPane.width / 132)))
  readonly property var source: Model.sources.find(s => s.mode === launcher.parsed.mode) || null
  readonly property string heading: launcher.argFor ? "Script arguments"
    : launcher.asking ? "Ask " + (launcher.agent ? launcher.agent.name : "the agent")
    : launcher.home ? "Favorites"
    : launcher.parsed.mode === "root" ? "Search results"
    : launcher.parsed.mode === "sources" ? "Search sources"
    : launcher.source ? launcher.source.name : "Search results"
  readonly property bool sidePreview: launcher.previewing && box.width >= 880
  readonly property string actionLabel: !launcher.selected ? "Open"
    : ["source", "quicklink"].includes(launcher.selected.kind) ? "Browse"
    : ["symbol", "clip", "calc"].includes(launcher.selected.kind) ? "Copy"
    : launcher.selected.kind === "snippet" ? "Paste"
    : launcher.selected.kind === "argument" ? "Continue"
    : launcher.selected.kind === "ask" ? (launcher.asking ? "Copy answer" : "Ask")
    : ["command", "script"].includes(launcher.selected.kind) ? "Run" : "Open"

  function iconFor(name) {
    return Quickshell.iconPath(name || "", true) || Quickshell.iconPath("application-x-executable", true)
  }

  function chooseSource(mode) {
    const source = Model.sources.find(s => s.mode === mode)
    if (!source)
      return
    launcher.argFor = null
    launcher.argValues = []
    launcher.pending = null
    launcher.asking = null
    launcher.query = source.prefix
    field.forceActiveFocus()
  }

  visible: open
  screen: place.screen
  WlrLayershell.namespace: "subcult-launcher"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"

  function search(q) {
    return Model.rank(launcher.apps, launcher.favorites, launcher.history, q, Date.now(), 50)
  }

  // The rows for a query: apps and commands, plus a calculator answer, a
  // command with its arguments, or a web search, as the query asks.
  function rows(q) {
    if (launcher.argFor)
      return [launcher.argumentRow()]
    if (launcher.asking)
      return [Object.assign({}, launcher.asking.row, { name: launcher.asking.row.name, genericName: launcher.asking.answer === "" ? "Asking…" : "Answered; Enter copies the answer" })]
    const p = Model.parseQuery(q)
    if (p.mode === "sources")
      return Model.sourceRows(p.text)
    if (["apps", "commands", "scripts", "snippets"].includes(p.mode)) {
      const catalog = p.mode === "apps" ? launcher.apps : p.mode === "commands" ? launcher.commands
        : p.mode === "scripts" ? launcher.scripts : launcher.snippets
      return Model.rank(catalog, launcher.favorites, launcher.history, p.text, Date.now(), 50, true)
    }
    const calc = launcher.calcResult.answer !== "" && launcher.calcResult.expr === launcher.calcExpr && launcher.calcExpr !== ""
      ? [{ kind: "calc", id: "calc", name: launcher.calcResult.answer, genericName: "= " + launcher.calcExpr + "   Enter copies the answer", icon: "accessories-calculator" }]
      : []
    if (p.mode === "calc")
      return calc
    if (p.mode === "web") {
      if (p.text === "")
        return Object.keys(launcher.quicklinks.links).sort().map(k => ({ kind: "quicklink", id: k, name: "@" + k, genericName: launcher.quicklinks.links[k].name, icon: "web-browser" }))
      const t = Model.webTarget(launcher.quicklinks, p.text)
      return t ? [launcher.webRow(t)] : []
    }
    if (p.mode === "files")
      return launcher.fileResult.text === p.text ? launcher.fileResult.rows : []
    if (p.mode === "symbols")
      return Model.rank(launcher.symbolItems, [], launcher.history, p.text, Date.now(), 50, true)
    if (p.mode === "clipboard") {
      if (p.text === "")
        return launcher.clips.length > 0 ? launcher.clips.concat([Model.clipClear]) : []
      return launcher.clips.filter(c => Model.match(c, p.text) > 0)
    }
    if (p.text === "")
      return Model.rank(launcher.apps, launcher.favorites, launcher.history, "", Date.now(), 50)
    let out = calc
    const alias = Model.resolveAlias(launcher.aliasNames, launcher.items, p.text)
    if (alias)
      out = out.concat([launcher.aliasRow(alias)])
    const call = Model.commandCall(launcher.commands, p.text)
    if (call && call.args.length > 0)
      out = out.concat([{ kind: "command", id: call.command.id, name: call.command.name + " " + call.args.join(" "), genericName: "Run " + call.command.id + " with these arguments", icon: "utilities-terminal", args: call.args, dangerous: call.command.dangerous, silent: call.command.silent }])
    const first = p.text.split(/\s+/)[0]
    const t = Model.webTarget(launcher.quicklinks, p.text)
    if (t && launcher.quicklinks.links[first] && t.key === first)
      out = out.concat([launcher.webRow(t)])
    out = out.concat(Model.rank(launcher.items, launcher.favorites, launcher.history, p.text, Date.now(), 50))
    if (out.length === 0 && t)
      out = [launcher.webRow(t)]
    const ask = Model.askRow(launcher.agent, p.text)
    return ask ? out.concat([ask]) : out
  }

  // An alias's item, with the rest of the line as its arguments.
  function aliasRow(a) {
    const it = a.item
    if (it.kind === "command" && a.rest !== "") {
      const args = a.rest.split(/\s+/)
      return Object.assign({}, it, { name: it.name + " " + args.join(" "), args: args })
    }
    if (it.kind === "script")
      return Object.assign({}, it, { given: Model.splitArgs(a.rest, (it.params || []).length) })
    return it
  }

  function argumentRow() {
    const s = launcher.argFor
    const i = launcher.argValues.length
    const param = s.params[i]
    return { kind: "argument", id: s.id, name: s.name, icon: s.icon,
      genericName: "Argument " + (i + 1) + " of " + s.params.length + ": " + param.placeholder
        + (param.optional ? " (optional)" : "") + "   Enter continues, Escape goes back" }
  }

  function webRow(t) {
    return { kind: "web", id: t.url, name: t.query === "" ? "Open " + t.name : "Search " + t.name + " for “" + t.query + "”", genericName: t.url, icon: "web-browser", url: t.url }
  }

  function show() {
    if (launcher.open)
      return
    Panels.close()
    launcher.query = ""
    launcher.pending = null
    launcher.argFor = null
    launcher.argValues = []
    launcher.index = 0
    commandList.running = true
    scriptList.running = true
    agentInfo.running = true
    place.open()
    launcher.open = true
  }

  function hide() {
    launcher.open = false
    launcher.pending = null
    launcher.asking = null
    launcher.argFor = null
    launcher.argValues = []
    launcher.query = ""
  }

  // Enter on a row. A dangerous command asks first: the next Enter
  // (confirmed) runs it, Escape goes back.
  function launch(row, confirmed) {
    if (!row)
      return
    if (row.kind === "source") {
      launcher.query = row.prefix
      field.forceActiveFocus()
      return
    }
    if (row.kind === "quicklink") {
      launcher.query = "@" + row.id + " "
      return
    }
    if (row.kind === "argument") {
      const values = launcher.argValues.concat([launcher.query.trim()])
      const script = launcher.argFor
      if (values[values.length - 1] === "" && !script.params[values.length - 1].optional)
        return
      if (values.length < script.params.length) {
        launcher.argValues = values
        launcher.query = ""
        return
      }
      launcher.runScript(script, values)
    } else if (row.kind === "script") {
      if (row.dangerous && !confirmed) {
        launcher.pending = row
        return
      }
      const given = row.given || []
      if (given.length < Model.requiredArgs(row)) {
        launcher.show()
        launcher.query = ""
        launcher.argValues = given
        launcher.argFor = row
        return
      }
      launcher.runScript(row, given)
    } else if (row.kind === "snippet") {
      launcher.paste(Model.expand(row.text, new Date(), Quickshell.clipboardText))
      launcher.remember(row.id)
    } else if (row.kind === "calc") {
      Quickshell.clipboardText = row.name
    } else if (row.kind === "symbol") {
      Quickshell.clipboardText = row.char
      launcher.remember(row.id)
    } else if (row.kind === "ask") {
      // The launcher stays open: the answer arrives in the preview pane.
      // Enter on the answered row copies the answer.
      if (launcher.asking && launcher.asking.answer !== "") {
        Quickshell.clipboardText = launcher.asking.answer
        launcher.hide()
        return
      }
      if (launcher.asking)
        return
      launcher.asking = { row: row, answer: "" }
      // A question dismissed with Escape may still be running: it is
      // stopped, and this one starts when it has exited.
      if (askRun.running) {
        askRun.stale = true
        askRun.running = false
      } else {
        askRun.start()
      }
      return
    } else if (row.kind === "clip") {
      clipAction.command = ["subcult", "clipboard", "copy", row.clipId]
      clipAction.running = true
    } else if (row.kind === "clipclear") {
      clipAction.command = ["subcult", "clipboard", "clear"]
      clipAction.running = true
      return
    } else if (row.kind === "file") {
      Quickshell.execDetached(["uwsm-app", "--", "xdg-open", row.path])
      launcher.remember(row.id)
    } else if (row.kind === "web") {
      Quickshell.execDetached(["uwsm-app", "--", "xdg-open", row.url])
    } else if (row.kind === "command") {
      if (row.dangerous && !confirmed) {
        launcher.pending = row
        return
      }
      Quickshell.execDetached(Model.commandArgv(row))
      launcher.remember(row.id)
    } else {
      Quickshell.execDetached(["uwsm-app", "--", row.id + ".desktop"])
      launcher.remember(row.id)
    }
    launcher.hide()
  }

  function runScript(script, values) {
    while (values.length > 0 && values[values.length - 1] === "")
      values = values.slice(0, -1)
    Quickshell.execDetached(Model.scriptArgv(script, values, Quickshell.env("HOME")))
    launcher.remember(script.id)
  }

  // Types the text into the window that had the focus, once the launcher
  // has closed and given it back.
  function paste(text) {
    Quickshell.execDetached(["sh", "-c", 'sleep 0.2; exec wtype -- "$1"', "sh", text])
  }

  // A hotkey bound to an alias: run its item as Enter would, opening the
  // launcher only to confirm or to ask for arguments.
  function runAlias(name) {
    const target = launcher.aliasNames[name]
    const item = launcher.items.find(i => i.id === target)
    if (!item) {
      console.warn("subcult launcher: alias", name, "names nothing:", target)
      return
    }
    if (item.dangerous) {
      launcher.show()
      launcher.pending = item
      return
    }
    launcher.launch(item, false)
  }

  function remember(id) {
    historyFile.setText(JSON.stringify(Model.record(launcher.history, id, Date.now(), 500)) + "\n")
  }

  function calculate() {
    if (launcher.calcExpr === "")
      return
    if (calc.running) {
      launcher.calcAgain = true
      return
    }
    calc.expr = launcher.calcExpr
    // Exchange rates are never fetched: the launcher makes no network calls.
    calc.command = ["qalc", "-t", "-set", "update exchange rates 0", calc.expr]
    calc.running = true
  }

  function clearHistory() {
    historyFile.setText("{}\n")
  }

  // The file search for the current query, once typing pauses. A search
  // already running is left to finish and the query searched again after.
  function findFiles() {
    if (launcher.parsed.mode !== "files" || launcher.parsed.text === "")
      return
    if (fd.running) {
      launcher.fdAgain = true
      return
    }
    fd.text = launcher.parsed.text
    fd.command = Model.fdArgv(fd.text, Quickshell.env("HOME"))
    fd.running = true
  }

  // The preview of the selected file: images show as they are, the rest
  // through a short read.
  function loadPreview() {
    const row = launcher.selected
    if (row && row.kind === "snippet") {
      launcher.preview = Model.expand(row.text, new Date(), Quickshell.clipboardText)
      return
    }
    if (row && row.kind === "clip" && !row.isImage) {
      if (previewRead.running) {
        launcher.previewAgain = true
        return
      }
      previewRead.path = row.id
      previewRead.command = ["subcult", "clipboard", "show", row.clipId]
      previewRead.running = true
      return
    }
    if (!row || row.kind !== "file" || Model.isImage(row.path)) {
      launcher.preview = ""
      return
    }
    if (previewRead.running) {
      launcher.previewAgain = true
      return
    }
    previewRead.path = row.path
    previewRead.command = Model.previewArgv(row.path)
    previewRead.running = true
  }

  onVisibleChanged: if (visible) field.forceActiveFocus()
  onResultsChanged: launcher.index = Model.move(0, 0, launcher.results.length)
  onQueryChanged: {
    launcher.pending = null
    launcher.asking = null
  }
  onArgForChanged: field.forceActiveFocus()
  onCalcExprChanged: if (launcher.calcExpr !== "") calcDelay.restart()
  onParsedChanged: {
    if (launcher.parsed.mode === "files" && launcher.parsed.text !== "")
      fdDelay.restart()
    if (launcher.parsed.mode === "symbols")
      launcher.wantSymbols = true
    if (launcher.parsed.mode === "clipboard" && !clipList.running)
      clipList.running = true
  }
  onSelectedChanged: {
    launcher.preview = ""
    launcher.loadPreview()
  }

  Timer {
    id: calcDelay
    interval: 120
    onTriggered: launcher.calculate()
  }

  Timer {
    id: fdDelay
    interval: 120
    onTriggered: launcher.findFiles()
  }

  Process {
    id: fd
    property string text: ""
    stdout: StdioCollector {
      onStreamFinished: launcher.fileResult = { text: fd.text, rows: Model.files(text, Quickshell.env("HOME")) }
    }
    onExited: if (launcher.fdAgain) {
      launcher.fdAgain = false
      launcher.findFiles()
    }
  }

  Process {
    id: clipList
    command: ["subcult", "clipboard", "list", "--json"]
    stdout: StdioCollector {
      onStreamFinished: launcher.clips = Model.clipboard(text)
    }
  }

  // copy puts an entry back and closes; clear empties the list and stays.
  Process {
    id: clipAction
    onExited: {
      if (clipAction.command[2] === "copy")
        launcher.hide()
      else
        clipList.running = true
    }
  }

  Process {
    id: askRun
    // The question this run was started for, and whether it was stopped
    // for a newer one: an answer is filed only under its own question.
    property string question: ""
    property bool stale: false
    function start() {
      askRun.question = launcher.asking.row.text
      askRun.stale = false
      askRun.command = ["subcult", "app", "ask", "--", askRun.question]
      askRun.running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (!askRun.stale && launcher.asking && launcher.asking.answer === "" && launcher.asking.row.text === askRun.question)
          launcher.asking = { row: launcher.asking.row, answer: text.trim() === "" ? "(no answer)" : text.trim() }
      }
    }
    onExited: {
      if (launcher.asking && launcher.asking.answer === "" && (askRun.stale || launcher.asking.row.text !== askRun.question))
        askRun.start()
    }
  }

  // The default agent, read each time the launcher opens (the default
  // picker may have changed it).
  Process {
    id: agentInfo
    running: true
    command: ["subcult", "app", "ask", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        const a = Model.agent(text)
        if (!Model.same(a, launcher.agent))
          launcher.agent = a
      }
    }
  }

  Process {
    id: previewRead
    property string path: ""
    stdout: StdioCollector {
      onStreamFinished: if (launcher.selected && (launcher.selected.path === previewRead.path || launcher.selected.id === previewRead.path)) launcher.preview = text
    }
    onExited: if (launcher.previewAgain) {
      launcher.previewAgain = false
      launcher.loadPreview()
    }
  }

  // Read once, the first time ":" is typed; absent when unicode-emoji is
  // not installed, leaving the symbols file.
  FileView {
    path: launcher.wantSymbols ? "/usr/share/unicode/emoji/emoji-test.txt" : ""
    printErrors: false
    onLoaded: launcher.emojiItems = Model.emoji(text())
  }

  FileView {
    path: launcher.systemDir + "symbols.json"
    blockLoading: true
    printErrors: false
    onLoaded: launcher.systemSymbols = text()
  }

  Process {
    id: calc
    property string expr: ""
    stdout: StdioCollector {
      onStreamFinished: launcher.calcResult = { expr: calc.expr, answer: Model.calcAnswer(text, calc.expr) }
    }
    onExited: if (launcher.calcAgain) {
      launcher.calcAgain = false
      launcher.calculate()
    }
  }

  // Read at start (aliases may name them) and again each time the launcher
  // opens, so new commands and scripts show up.
  Process {
    id: commandList
    running: true
    command: ["subcult", "commands", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        const c = Model.commands(text)
        if (!Model.same(c, launcher.commands))
          launcher.commands = c
      }
    }
  }

  // The script commands: each executable file's path and first lines.
  Process {
    id: scriptList
    running: true
    command: ["sh", "-c", 'for f in "$1"/*; do [ -f "$f" ] && [ -x "$f" ] || continue; printf "\\036%s\\n" "$f"; head -n 40 -- "$f"; done', "sh", launcher.scriptDir]
    stdout: StdioCollector {
      onStreamFinished: {
        const s = Model.scripts(text)
        if (!Model.same(s, launcher.scripts))
          launcher.scripts = s
      }
    }
  }

  // One global shortcut per alias, for Hyprland bindings:
  //   sub.bind("SUPER + ALT + U", "Update", sub.alias("up"))
  Variants {
    model: Object.keys(launcher.aliasNames)
    delegate: GlobalShortcut {
      required property string modelData
      appid: "subcult"
      name: "alias." + modelData
      description: "Launcher alias " + modelData
      onPressed: launcher.runAlias(modelData)
    }
  }

  OverlayScreen {
    id: place
  }

  GlobalShortcut {
    appid: "subcult"
    name: "launcher-toggle"
    description: "Open or close the launcher"
    onPressed: launcher.open ? launcher.hide() : launcher.show()
  }

  GlobalShortcut {
    appid: "subcult"
    name: "clipboard"
    description: "Open the launcher on the clipboard history"
    onPressed: {
      launcher.show()
      launcher.query = "$"
    }
  }

  IpcHandler {
    target: "subcult.launcher"
    function open(): void { launcher.show() }
    function close(): void { launcher.hide() }
    function toggle(): void { launcher.open ? launcher.hide() : launcher.show() }
    function clearHistory(): void { launcher.clearHistory() }
    // Used by the tests: type a query, press Enter, read the state.
    function type(text: string): void { launcher.show(); launcher.query = text }
    function enter(): void { launcher.launch(launcher.pending || launcher.results[launcher.index], launcher.pending !== null) }
    function last(): void { launcher.index = Model.move(launcher.results.length - 1, 0, launcher.results.length) }
    // What an alias's global shortcut does.
    function hotkey(name: string): void { launcher.runAlias(name) }
    function source(mode: string): void { launcher.show(); launcher.chooseSource(mode) }
    function state(): string {
      return JSON.stringify({
        query: launcher.query,
        pending: launcher.pending ? launcher.pending.id : "",
        argument: launcher.argFor ? launcher.argValues.length + 1 : 0,
        mode: launcher.parsed.mode,
        heading: launcher.heading,
        width: box.width,
        height: box.height,
        columns: launcher.columns,
        index: launcher.index,
        inputFocused: field.activeFocus,
        bounds: [box.x, box.y, box.width, box.height],
        previewBounds: launcher.previewing ? [previewPane.x, previewPane.y, previewPane.width, previewPane.height] : [],
        sidePreview: launcher.sidePreview,
        placeholderCut: placeholder.truncated,
        aliases: Object.keys(launcher.aliasNames),
        rows: launcher.results.map(r => ({ kind: r.kind || "app", id: r.id, name: r.name, url: r.url || "" })),
        preview: launcher.previewing ? (launcher.selected.kind === "symbol" ? launcher.selected.char
          : launcher.selected.kind === "ask" ? (launcher.asking ? launcher.asking.answer : "")
          : launcher.selected.kind === "clip" && launcher.selected.isImage ? launcher.selected.file : launcher.preview) : ""
      })
    }
    // The ids a query ranks, as JSON (used by the tests).
    function search(q: string): string { return JSON.stringify(launcher.search(q).map(a => a.id)) }
  }

  Process {
    running: true
    command: ["mkdir", "-p", launcher.dataHome + "/applications"]
    onExited: launcher.entriesReady = true
  }

  FileView {
    path: launcher.systemDir + "favorites.json"
    blockLoading: true
    printErrors: false
    onLoaded: launcher.systemFavorites = Model.favorites(text()) || []
  }

  FileView {
    path: launcher.systemDir + "quicklinks.json"
    blockLoading: true
    printErrors: false
    onLoaded: launcher.systemQuicklinks = text()
  }

  WatchedFile {
    id: userFavorites
    path: launcher.userDir + "favorites.json"
  }

  WatchedFile {
    id: userQuicklinks
    path: launcher.userDir + "quicklinks.json"
  }

  FileView {
    path: launcher.systemDir + "snippets.json"
    blockLoading: true
    printErrors: false
    onLoaded: launcher.systemSnippets = text()
  }

  WatchedFile {
    id: userSnippets
    path: launcher.userDir + "snippets.json"
  }

  WatchedFile {
    id: aliasFile
    path: launcher.userDir + "aliases.json"
  }

  WatchedFile {
    id: historyFile
    path: launcher.historyPath
  }

  // A click outside the box closes the launcher.
  MouseArea {
    anchors.fill: parent
    onClicked: launcher.hide()
  }

  Rectangle {
    id: box
    anchors.centerIn: parent
    width: Math.min(960, Math.max(0, parent.width - 32))
    height: Math.min(560, Math.max(0, parent.height - 64))
    color: Theme.mantle
    border.width: 1
    border.color: Theme.border

    MouseArea { anchors.fill: parent }

    // Search remains focused while arrows move through the results.
    Rectangle {
      id: searchBar
      x: 1
      y: 1
      width: parent.width - 2
      height: 64
      color: Theme.base
      Text {
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        text: "⌕"
        color: Theme.accent
        font.pixelSize: 26
      }
      TextInput {
        id: field
        x: 54
        width: parent.width - 180
        height: parent.height
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.selection
        selectedTextColor: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize + 7
        clip: true
        text: launcher.query
        onTextEdited: launcher.query = text
        Keys.onPressed: (event) => {
          const n = launcher.results.length
          const across = launcher.home ? 1 : 0
          const down = launcher.home ? launcher.columns : 1
          if (event.key === Qt.Key_Escape && launcher.pending)
            launcher.pending = null
          else if (event.key === Qt.Key_Escape && launcher.asking)
            launcher.asking = null
          else if (event.key === Qt.Key_Escape && launcher.argFor) {
            launcher.argFor = null
            launcher.argValues = []
            launcher.query = ""
          }
          else if (event.key === Qt.Key_Escape && launcher.query !== "")
            launcher.chooseSource("root")
          else if (event.key === Qt.Key_Escape)
            launcher.hide()
          else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && launcher.pending) {
            if (Model.confirms(event.isAutoRepeat))
              launcher.launch(launcher.pending, true)
          }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            launcher.launch(launcher.results[launcher.index], false)
          else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
            launcher.index = Model.move(launcher.index, event.key === Qt.Key_Tab ? 1 : down, n)
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
            launcher.index = Model.move(launcher.index, event.key === Qt.Key_Backtab ? -1 : -down, n)
          else if (across && event.key === Qt.Key_Right)
            launcher.index = Model.move(launcher.index, 1, n)
          else if (across && event.key === Qt.Key_Left)
            launcher.index = Model.move(launcher.index, -1, n)
          else
            return
          event.accepted = true
        }
        Text {
          id: placeholder
          visible: field.text === ""
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: launcher.argFor ? launcher.argFor.params[launcher.argValues.length].placeholder
            : "Search apps, commands and more…"
          color: Theme.subtext
          font: field.font
        }
      }
      Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 92
        height: 28
        color: sourceButton.containsMouse ? Theme.surface : "transparent"
        border.width: 1
        border.color: Theme.surface
        Text {
          anchors.centerIn: parent
          text: "/  Sources"
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize + 1
        }
        MouseArea {
          id: sourceButton
          anchors.fill: parent
          hoverEnabled: true
          onClicked: { launcher.query = "/"; field.forceActiveFocus() }
        }
      }
    }
    Rectangle { x: 1; y: searchBar.height; width: parent.width - 2; height: 1; color: Theme.surface }

    Row {
      id: body
      x: 16
      y: searchBar.height + 16
      width: parent.width - 32
      height: parent.height - searchBar.height - footer.height - 32
      spacing: 16

      Flickable {
        id: navigation
        height: body.height
        contentHeight: sourceList.implicitHeight
        clip: true
        visible: box.width >= 700
        width: visible ? 168 : 0
        Column {
          id: sourceList
          width: parent.width
          spacing: 2
          Text {
            height: 28
            leftPadding: 10
            text: "LIBRARY"
            color: Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 1
            font.letterSpacing: 1.2
          }
          Repeater {
            model: Model.sources
            delegate: Rectangle {
              id: destination
              required property var modelData
              readonly property bool selected: launcher.parsed.mode === modelData.mode
                && (modelData.mode !== "root" || launcher.home)
              width: navigation.width
              height: 34
              color: selected ? Theme.selection : sourceMouse.containsMouse ? Theme.surface : "transparent"
              Rectangle {
                visible: destination.selected
                width: 2
                height: parent.height - 12
                x: 0
                y: 6
                color: Theme.accent
              }
              Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 18
                text: destination.modelData.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: destination.selected ? Theme.text : Theme.subtext
                font.family: Style.uiFontFamily
                font.pixelSize: Style.fontSize + 2
                font.weight: destination.selected ? Font.DemiBold : Font.Normal
              }
              MouseArea {
                id: sourceMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: launcher.chooseSource(destination.modelData.mode)
              }
            }
          }
        }
      }
      Rectangle { visible: navigation.visible; width: visible ? 1 : 0; height: parent.height; color: Theme.surface }

      Column {
        id: resultsPane
        width: body.width - (navigation.visible ? navigation.width + 33 : 0)
          - (launcher.sidePreview ? Math.floor(body.width * 0.34) + 16 : 0)
        height: body.height
        spacing: 8
        readonly property real available: Math.max(0, height - sectionTitle.height - 8
          - (confirmation.visible ? confirmation.height + 8 : 0)
          - (launcher.previewing && !launcher.sidePreview ? previewPane.height + 8 : 0))
        Row {
          id: sectionTitle
          width: parent.width
          height: 28
          Text {
            width: parent.width - countLabel.implicitWidth
            text: launcher.heading
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize + 3
            font.weight: Font.DemiBold
          }
          Text {
            id: countLabel
            text: launcher.results.length ? String(launcher.results.length) : ""
            color: Theme.subtext
            font.family: Style.fontFamily
            font.pixelSize: Style.fontSize + 1
          }
        }

        Rectangle {
          id: confirmation
          visible: launcher.pending !== null
          width: parent.width
          height: visible ? confirm.implicitHeight + 2 * Style.spacing : 0
          color: Theme.base
          border.width: 1
          border.color: Theme.warning

          Text {
            id: confirm
            x: Style.spacing
            y: Style.spacing
            width: parent.width - 2 * Style.spacing
            text: launcher.pending ? "“" + (launcher.pending.kind === "command" ? "subcult " : "") + launcher.pending.name + "” is marked dangerous. Enter runs it; Escape goes back." : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.warning
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize + 1
          }
        }


        GridView {
          id: grid
          visible: launcher.home
          width: parent.width
          height: visible ? Math.min(Math.ceil(count / launcher.columns) * cellHeight, resultsPane.available) : 0
          cellWidth: width / launcher.columns
          cellHeight: 100
          clip: true
          interactive: contentHeight > height
          model: launcher.home ? launcher.results : []
          currentIndex: launcher.index
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
          delegate: Rectangle {
            id: tile
            required property var modelData
            required property int index
            width: grid.cellWidth - 6
            height: grid.cellHeight - 6
            color: tile.index === launcher.index ? Theme.selection : tileMouse.containsMouse ? Theme.surface : "transparent"
            border.width: tile.index === launcher.index ? 1 : 0
            border.color: Theme.accent
            Column {
              anchors.centerIn: parent
              width: parent.width - 16
              spacing: 10
              IconImage {
                id: tileIcon
                anchors.horizontalCenter: parent.horizontalCenter
                implicitSize: 36
                visible: source !== ""
                source: launcher.iconFor(tile.modelData.icon)
                layer.enabled: String(tile.modelData.icon || "").endsWith("-symbolic") && Quickshell.hasThemeIcon(tile.modelData.icon)
                // Flatten symbolic luminance before applying the palette.
                layer.effect: MultiEffect { contrast: -1; brightness: 0.5; colorization: 1; colorizationColor: Theme.text }
              }
              Text {
                visible: !tileIcon.visible
                width: parent.width
                height: 36
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: String(tile.modelData.name || tile.modelData.id).charAt(0).toUpperCase()
                color: Theme.accent
                font.family: Style.uiFontFamily
                font.pixelSize: 28
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.modelData.name || tile.modelData.id
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.text
                font.family: Style.uiFontFamily
                font.pixelSize: Style.fontSize + 2
              }
            }
            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              onPositionChanged: if (containsMouse) launcher.index = tile.index
              onClicked: launcher.launch(tile.modelData, false)
            }
          }
        }
        ListView {
          id: list
          visible: !launcher.home
          width: parent.width
          height: visible ? Math.min(count * 52, resultsPane.available) : 0
          clip: true
          model: launcher.home ? [] : launcher.results
          currentIndex: launcher.index
          highlightMoveDuration: 0
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: 52
            color: row.index === launcher.index ? Theme.selection : rowMouse.containsMouse ? Theme.surface : "transparent"
            Rectangle { visible: row.index === launcher.index; width: 2; height: 30; y: 11; color: Theme.accent }
            IconImage {
              id: icon
              anchors.verticalCenter: parent.verticalCenter
              x: 12
              implicitSize: 24
              visible: row.modelData.kind !== "symbol"
              source: visible ? launcher.iconFor(row.modelData.icon) : ""
              layer.enabled: String(row.modelData.icon || "").endsWith("-symbolic") && Quickshell.hasThemeIcon(row.modelData.icon)
              layer.effect: MultiEffect { contrast: -1; brightness: 0.5; colorization: 1; colorizationColor: Theme.text }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: 12
              width: 24
              visible: row.modelData.kind === "symbol" || icon.source === ""
              horizontalAlignment: Text.AlignHCenter
              text: row.modelData.kind === "symbol" ? row.modelData.char
                : String(row.modelData.name || row.modelData.id).charAt(0).toUpperCase()
              textFormat: Text.PlainText
              color: Theme.text
              font.pixelSize: Style.fontSize + 10
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              x: 48
              width: parent.width - 60 - (row.modelData.kind === "source" ? 76 : 0)
              spacing: 3
              Text {
                width: parent.width
                text: row.modelData.name || row.modelData.id
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.text
                font.family: Style.uiFontFamily
                font.pixelSize: Style.fontSize + 3
              }
              Text {
                visible: text !== ""
                width: parent.width
                text: row.modelData.genericName || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Style.uiFontFamily
                font.pixelSize: Style.fontSize
              }
            }
            Text {
              visible: row.modelData.kind === "source"
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.hint || ""
              color: Theme.subtext
              font.family: Style.fontFamily
              font.pixelSize: Style.fontSize
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              onPositionChanged: if (containsMouse) launcher.index = row.index
              onClicked: launcher.launch(row.modelData, false)
            }
          }
        }
        Text {
          visible: launcher.results.length === 0
          topPadding: 16
          width: parent.width
          text: launcher.home ? "Your favorites will appear here. Browse Applications to get started."
            : launcher.parsed.mode === "sources" ? "No matching sources"
            : launcher.parsed.mode === "scripts" ? "No script commands yet"
            : launcher.parsed.mode === "snippets" ? "No snippets yet"
            : launcher.parsed.mode === "calc" ? (launcher.parsed.text === "" ? "Enter an expression, such as 25 * 4 or 5 km to mi" : "No answer")
            : launcher.parsed.mode === "files" ? (launcher.parsed.text === "" ? "Type part of a file name; fd searches your home folder"
              : launcher.fileResult.text === launcher.parsed.text ? "Nothing found" : "Searching…")
            : launcher.parsed.mode === "symbols" && launcher.parsed.text === "" ? "Type an emoji or symbol name; Enter copies it"
            : launcher.parsed.mode === "clipboard" ? (launcher.clips.length === 0 ? "Clipboard history is empty" : "Nothing found")
            : "Nothing found"
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize + 2
        }
      }

    }

    Rectangle {
      id: previewPane
      visible: launcher.previewing
      x: body.x + resultsPane.x + (launcher.sidePreview ? resultsPane.width + 16 : 0)
      y: body.y + (launcher.sidePreview ? 0 : body.height - height)
      width: launcher.sidePreview ? Math.floor(body.width * 0.34) : resultsPane.width
      height: visible ? (launcher.sidePreview ? body.height : Math.min(160, body.height * 0.35)) : 0
      color: Theme.base
      border.width: 1
      border.color: Theme.surface
      clip: true

      Text {
        x: Style.spacing
        y: Style.spacing
        text: "PREVIEW"
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
        font.letterSpacing: 1
      }
      Text {
        visible: launcher.selected !== null && launcher.selected.kind === "symbol"
        anchors.centerIn: parent
        text: visible ? launcher.selected.char + "\n" : ""
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        color: Theme.text
        font.pixelSize: 56
      }
      Image {
        id: imagePreview
        readonly property bool wanted: launcher.selected !== null && ((launcher.selected.kind === "file" && Model.isImage(launcher.selected.path))
          || (launcher.selected.kind === "clip" && launcher.selected.isImage))
        visible: wanted
        anchors.fill: parent
        anchors.margins: 8
        anchors.topMargin: 28
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: 1024
        sourceSize.height: 1024
        source: wanted ? "file://" + (launcher.selected.kind === "clip" ? launcher.selected.file : launcher.selected.path) : ""
      }
      Flickable {
        id: previewScroll
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 32
        visible: launcher.selected !== null && launcher.selected.kind !== "symbol" && !imagePreview.wanted
        contentWidth: width
        contentHeight: previewText.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Text {
          id: previewText
          width: parent.width
          readonly property bool isAsk: launcher.selected !== null && launcher.selected.kind === "ask"
          text: !isAsk ? launcher.preview : launcher.asking
            ? (launcher.asking.answer === "" ? "Asking " + launcher.agent.name + "…" : launcher.asking.answer)
            : "Enter sends the text to " + (launcher.agent ? launcher.agent.name : "the agent") + "'s provider. It leaves this machine."
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
          color: isAsk && !launcher.asking ? Theme.warning : Theme.text
          font.family: isAsk ? Style.uiFontFamily : Style.fontFamily
          font.pixelSize: Style.fontSize + (isAsk ? 2 : 1)
          onTextChanged: previewScroll.contentY = 0
        }
      }
      Rectangle {
        visible: previewScroll.visible && previewScroll.contentHeight > previewScroll.height
        width: 2
        height: Math.max(16, previewScroll.height * previewScroll.height / previewScroll.contentHeight)
        x: parent.width - 5
        y: previewScroll.y + Math.max(0, previewScroll.contentY) / Math.max(1, previewScroll.contentHeight - previewScroll.height) * (previewScroll.height - height)
        color: Theme.border
      }
    }
    Rectangle { x: 1; y: footer.y; width: parent.width - 2; height: 1; color: Theme.surface }
    Item {
      id: footer
      x: 16
      y: parent.height - height
      width: parent.width - 32
      height: 42
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: launcher.home ? "↑ ↓ ← →  Navigate" : "↑ ↓  Navigate"
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: !launcher.selected || (launcher.asking && launcher.asking.answer === "")
          ? "Esc " + (launcher.query !== "" ? "Back" : "Close")
          : launcher.pending ? "↵ Confirm    Esc Back"
          : "↵ " + launcher.actionLabel
            + "    Esc " + (launcher.query !== "" || launcher.argFor ? "Back" : "Close")
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
    }
  }
}
