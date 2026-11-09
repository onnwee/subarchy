import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

// A user file that may not exist yet. FileView watches a file only once it
// exists, so the folder is created (empty) and watched as well: creating,
// replacing or deleting the file reloads it. Nothing polls.
// changed(live): live is false for the first read at start.
Item {
  id: root

  required property string path
  readonly property string dir: path.substring(0, path.lastIndexOf("/"))
  readonly property string name: path.substring(path.lastIndexOf("/") + 1)
  property string text: ""
  property bool exists: false
  property bool settled: false

  signal changed(bool live)

  function setText(t) {
    file.setText(t)
    root.text = t
    root.exists = true
    root.changed(root.settled)
  }

  function update(t, present) {
    const live = root.settled
    root.settled = true
    if (t === root.text && present === root.exists && live)
      return
    root.text = t
    root.exists = present
    root.changed(live)
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.update(text(), true)
    onLoadFailed: root.update("", false)
    onFileChanged: reload()
  }

  Process {
    running: true
    command: ["mkdir", "-p", root.dir]
    onExited: folder.folder = "file://" + root.dir
  }

  FolderListModel {
    id: folder
    nameFilters: [root.name]
    showDirs: false
    showHidden: true
    onCountChanged: file.reload()
  }
}
