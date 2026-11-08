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
// shortcut. Typing searches the desktop entries; an empty query shows the
// favorites. Pinned favorites come first, then frecency from the history
// file. Quickshell keeps the app list and refreshes it when desktop entries
// change, but only in folders that existed when it first read them, so the
// user's applications folder is created first. The window exists only while
// open.
PanelWindow { // qmllint disable uncreatable-type
  id: launcher

  property bool open: false
  property var openScreen: null
  property string query: ""
  property int index: 0

  readonly property string systemPath: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/launcher/favorites.json"
  readonly property string userPath: Quickshell.env("HOME") + "/.config/subcult/launcher/favorites.json"
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
  readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/launcher/history.json"

  property var systemFavorites: []
  property bool entriesReady: false
  readonly property var favorites: Model.favorites(userFavorites.text) || launcher.systemFavorites
  readonly property var history: Model.parseHistory(historyFile.text)
  readonly property var apps: !launcher.entriesReady ? [] : DesktopEntries.applications.values
    .filter(e => !e.noDisplay)
    .map(e => ({ id: e.id, name: e.name, genericName: e.genericName, keywords: e.keywords, icon: e.icon }))
  readonly property var results: launcher.open ? launcher.search(launcher.query) : []
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

  function show() {
    if (launcher.open)
      return
    launcher.query = ""
    launcher.index = 0
    launcher.openScreen = Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    launcher.open = true
  }

  function hide() {
    launcher.open = false
    launcher.query = ""
  }

  function launch(app) {
    if (!app)
      return
    Quickshell.execDetached(["uwsm-app", "--", app.id + ".desktop"])
    historyFile.setText(JSON.stringify(Model.record(launcher.history, app.id, Date.now(), 500)) + "\n")
    launcher.hide()
  }

  function clearHistory() {
    historyFile.setText("{}\n")
  }

  onVisibleChanged: if (visible) field.forceActiveFocus()
  onResultsChanged: launcher.index = Model.move(0, 0, launcher.results.length)

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
    // The ids a query ranks, as JSON (used by the tests).
    function search(q: string): string { return JSON.stringify(launcher.search(q).map(a => a.id)) }
  }

  Process {
    running: true
    command: ["mkdir", "-p", launcher.dataHome + "/applications"]
    onExited: launcher.entriesReady = true
  }

  FileView {
    path: launcher.systemPath
    blockLoading: true
    printErrors: false
    onLoaded: launcher.systemFavorites = Model.favorites(text()) || []
  }

  WatchedFile {
    id: userFavorites
    path: launcher.userPath
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
            if (event.key === Qt.Key_Escape)
              launcher.hide()
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              launcher.launch(launcher.results[launcher.index])
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
            text: "Search apps"
            color: Theme.muted
            font: field.font
          }
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
            onClicked: launcher.launch(tile.modelData)
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
            onClicked: launcher.launch(row.modelData)
          }
        }
      }

      Text {
        visible: launcher.results.length === 0
        width: parent.width
        text: launcher.home ? "No favorites yet: add app ids to ~/.config/subcult/launcher/favorites.json" : "No matching apps"
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.muted
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
    }
  }
}
