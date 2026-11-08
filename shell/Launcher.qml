pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import "LauncherModel.js" as Model

// The launcher (ADR 0057), opened with Super+Space through a global
// shortcut. Typing searches the desktop entries and the subcult commands;
// an empty query shows the favorites. Pinned favorites come first, then
// frecency from the history file. Math gets an inline qalc answer ("=" asks
// the calculator alone); "@" and a query with no match search the web. Quickshell keeps the app list and refreshes it when desktop entries
// change, but only in folders that existed when it first read them, so the
// user's applications folder is created first. The window exists only while
// open.
PanelWindow { // qmllint disable uncreatable-type
  id: launcher

  property bool open: false
  property var openScreen: null
  property string query: ""
  property int index: 0

  // A dangerous command waiting for Enter to confirm it.
  property var pending: null
  property var commands: []
  property var calcResult: ({ expr: "", answer: "" })
  property bool calcAgain: false

  readonly property string systemDir: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/launcher/"
  readonly property string userDir: Quickshell.env("HOME") + "/.config/subcult/launcher/"
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
  readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/launcher/history.json"

  property var systemFavorites: []
  property string systemQuicklinks: ""
  property bool entriesReady: false
  readonly property var favorites: Model.favorites(userFavorites.text) || launcher.systemFavorites
  readonly property var history: Model.parseHistory(historyFile.text)
  readonly property var apps: !launcher.entriesReady ? [] : DesktopEntries.applications.values
    .filter(e => !e.noDisplay)
    .map(e => ({ id: e.id, name: e.name, genericName: e.genericName, keywords: e.keywords, icon: e.icon }))
  readonly property var quicklinks: Model.quicklinks(launcher.systemQuicklinks, userQuicklinks.text)
  readonly property var parsed: Model.parseQuery(launcher.query)
  readonly property string calcExpr: launcher.parsed.mode === "calc"
    || (launcher.parsed.mode === "root" && Model.looksLikeMath(launcher.parsed.text)) ? launcher.parsed.text : ""
  readonly property var results: launcher.open ? launcher.rows(launcher.query) : []
  readonly property bool home: launcher.query.trim() === ""
  readonly property int columns: 4

  visible: open
  screen: openScreen
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
    const p = Model.parseQuery(q)
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
    if (p.text === "")
      return Model.rank(launcher.apps, launcher.favorites, launcher.history, "", Date.now(), 50)
    let out = calc
    const call = Model.commandCall(launcher.commands, p.text)
    if (call && call.args.length > 0)
      out = out.concat([{ kind: "command", id: call.command.id, name: call.command.name + " " + call.args.join(" "), genericName: "Run " + call.command.id + " with these arguments", icon: "utilities-terminal", args: call.args, dangerous: call.command.dangerous }])
    const first = p.text.split(/\s+/)[0]
    const t = Model.webTarget(launcher.quicklinks, p.text)
    if (t && launcher.quicklinks.links[first] && t.key === first)
      out = out.concat([launcher.webRow(t)])
    out = out.concat(Model.rank(launcher.apps.concat(launcher.commands), launcher.favorites, launcher.history, p.text, Date.now(), 50))
    if (out.length === 0 && t)
      out = [launcher.webRow(t)]
    return out
  }

  function webRow(t) {
    return { kind: "web", id: t.url, name: t.query === "" ? "Open " + t.name : "Search " + t.name + " for “" + t.query + "”", genericName: t.url, icon: "web-browser", url: t.url }
  }

  function show() {
    if (launcher.open)
      return
    launcher.query = ""
    launcher.pending = null
    launcher.index = 0
    commandList.running = true
    launcher.openScreen = Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    launcher.open = true
  }

  function hide() {
    launcher.open = false
    launcher.pending = null
    launcher.query = ""
  }

  // Enter on a row. A dangerous command asks first: the next Enter
  // (confirmed) runs it, Escape goes back.
  function launch(row, confirmed) {
    if (!row)
      return
    if (row.kind === "quicklink") {
      launcher.query = "@" + row.id + " "
      return
    }
    if (row.kind === "calc") {
      Quickshell.clipboardText = row.name
    } else if (row.kind === "web") {
      Quickshell.execDetached(["uwsm-app", "--", "xdg-open", row.url])
    } else if (row.kind === "command") {
      if (row.dangerous && !confirmed) {
        launcher.pending = row
        return
      }
      // In a terminal that stays open, so the output can be read.
      const words = row.id.split(" ").slice(1).concat(row.args || [])
      Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "sh", "-c",
        'subcult "$@"; s=$?; printf "\\n[exit %d] Press Enter to close." "$s"; read -r _', "sh"].concat(words))
      launcher.remember(row.id)
    } else {
      Quickshell.execDetached(["uwsm-app", "--", row.id + ".desktop"])
      launcher.remember(row.id)
    }
    launcher.hide()
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

  onVisibleChanged: if (visible) field.forceActiveFocus()
  onResultsChanged: launcher.index = Model.move(0, 0, launcher.results.length)
  onQueryChanged: launcher.pending = null
  onCalcExprChanged: if (launcher.calcExpr !== "") calcDelay.restart()

  Timer {
    id: calcDelay
    interval: 120
    onTriggered: launcher.calculate()
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

  // Read again each time the launcher opens, so new commands show up.
  Process {
    id: commandList
    command: ["subcult", "commands", "--json"]
    stdout: StdioCollector {
      onStreamFinished: launcher.commands = Model.commands(text)
    }
  }

  GlobalShortcut {
    appid: "subcult"
    name: "launcher-toggle"
    description: "Open or close the launcher"
    onPressed: launcher.open ? launcher.hide() : launcher.show()
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
    function state(): string {
      return JSON.stringify({
        query: launcher.query,
        pending: launcher.pending ? launcher.pending.id : "",
        rows: launcher.results.map(r => ({ kind: r.kind || "app", id: r.id, name: r.name, url: r.url || "" }))
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
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(parent.height * 0.2)
    width: 560
    height: content.implicitHeight + 2 * Style.spacing
    color: Theme.mantle
    border.width: 1
    border.color: Theme.border

    // Swallow clicks on the box so they do not close it.
    MouseArea {
      anchors.fill: parent
    }

    Column {
      id: content
      x: Style.spacing
      y: Style.spacing
      width: parent.width - 2 * Style.spacing
      spacing: Style.spacing

      Rectangle {
        width: parent.width
        height: 36
        color: Theme.base
        border.width: 1
        border.color: Theme.surface

        TextInput {
          id: field
          anchors.fill: parent
          anchors.leftMargin: Style.spacing
          anchors.rightMargin: Style.spacing
          verticalAlignment: TextInput.AlignVCenter
          color: Theme.text
          selectionColor: Theme.selection
          selectedTextColor: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize + 4
          text: launcher.query
          onTextEdited: launcher.query = text

          Keys.onPressed: (event) => {
            const n = launcher.results.length
            const across = launcher.home ? 1 : 0
            const down = launcher.home ? launcher.columns : 1
            if (event.key === Qt.Key_Escape && launcher.pending)
              launcher.pending = null
            else if (event.key === Qt.Key_Escape)
              launcher.hide()
            else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && launcher.pending)
              launcher.launch(launcher.pending, true)
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
            visible: field.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: "Search apps and commands, = calculate, @ search the web"
            color: Theme.muted
            font: field.font
          }
        }
      }

      // A dangerous command waits for confirmation.
      Rectangle {
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
          text: launcher.pending ? "“subcult " + launcher.pending.name + "” is marked dangerous. Enter runs it; Escape goes back." : ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Theme.warning
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize + 1
        }
      }

      // Home screen: the favorites grid.
      GridView {
        id: grid
        visible: launcher.home
        width: parent.width
        height: visible ? Math.ceil(count / launcher.columns) * cellHeight : 0
        cellWidth: width / launcher.columns
        cellHeight: 84
        interactive: false
        model: launcher.home ? launcher.results : []
        currentIndex: launcher.index

        delegate: Rectangle {
          id: tile
          required property var modelData
          required property int index
          width: grid.cellWidth - 4
          height: grid.cellHeight - 4
          color: tile.index === launcher.index ? Theme.selection : "transparent"
          border.width: tile.index === launcher.index ? 1 : 0
          border.color: Theme.accent

          Column {
            anchors.centerIn: parent
            width: parent.width - 8
            spacing: 4
            IconImage {
              anchors.horizontalCenter: parent.horizontalCenter
              implicitSize: 40
              source: Quickshell.iconPath(tile.modelData.icon || "", "application-x-executable")
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: tile.modelData.name || tile.modelData.id
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Theme.text
              font.family: Style.uiFontFamily
              font.pixelSize: Style.fontSize
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: launcher.launch(tile.modelData, false)
          }
        }
      }

      // Search results.
      ListView {
        id: list
        visible: !launcher.home
        width: parent.width
        height: visible ? Math.min(count, 8) * 40 : 0
        clip: true
        model: launcher.home ? [] : launcher.results
        currentIndex: launcher.index
        highlightMoveDuration: 0

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index
          width: list.width
          height: 40
          color: row.index === launcher.index ? Theme.selection : "transparent"

          IconImage {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            x: Style.spacing
            implicitSize: 24
            source: Quickshell.iconPath(row.modelData.icon || "", "application-x-executable")
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: icon.right
            anchors.leftMargin: Style.spacing
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing
            Text {
              width: parent.width
              text: row.modelData.name || row.modelData.id
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Theme.text
              font.family: Style.uiFontFamily
              font.pixelSize: Style.fontSize + 1
            }
            Text {
              visible: text !== ""
              width: parent.width
              text: row.modelData.genericName || ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Theme.subtext
              font.family: Style.uiFontFamily
              font.pixelSize: Style.fontSize - 1
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: launcher.launch(row.modelData, false)
          }
        }
      }

      Text {
        visible: launcher.results.length === 0
        width: parent.width
        text: launcher.home ? "No favorites yet: add app ids to ~/.config/subcult/launcher/favorites.json"
          : launcher.parsed.mode === "calc" ? "No answer" : "Nothing found"
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.muted
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
    }
  }
}
