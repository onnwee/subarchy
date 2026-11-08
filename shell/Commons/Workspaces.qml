pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "WorkspacesModel.js" as Model

// Workspace names (ADR 0048 layering): the system file under
// ~/.config/subcult/shell/workspaces.json, which is watched, so edits
// show in the bar and the switch overlay at once.
Singleton {
  id: root

  readonly property string systemPath: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/shell/workspaces.json"
  readonly property string userPath: Quickshell.env("HOME") + "/.config/subcult/shell/workspaces.json"

  property string systemText: ""
  readonly property var names: Model.parse(systemText, userFile.text)

  function label(id) {
    return Model.label(root.names, id)
  }

  function title(id) {
    return Model.title(root.names, id)
  }

  FileView {
    path: root.systemPath
    blockLoading: true
    printErrors: false
    onLoaded: root.systemText = text()
  }

  WatchedFile {
    id: userFile
    path: root.userPath
  }
}
