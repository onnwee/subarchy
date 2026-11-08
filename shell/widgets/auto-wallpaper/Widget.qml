import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Rotates the wallpaper on a schedule (stage 3, off by default: add
// "subcult.auto-wallpaper" to the bar layout). The widget's timer follows
// Power; on battery it waits unless `onBattery` is set. It writes the
// chosen image's path to ~/.local/state/subcult/wallpaper, which the
// background watches. Click goes to the next image now. Settings:
// directory (the images), mode (sequential or shuffle), onBattery.
BarWidget {
  id: root

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/wallpaper"
  readonly property string directory: String(settings.directory || "")
  readonly property var images: {
    const names = []
    for (let i = 0; i < folder.count; i++)
      names.push(folder.get(i, "fileName"))
    return Model.images(names)
  }
  readonly property string current: stateFile.text.trim()
  readonly property bool active: Model.active(shell.power ? shell.power.onBattery : false, settings.onBattery === true)

  implicitWidth: button.implicitWidth

  function rotate() {
    const name = Model.next(root.images, Model.fileName(root.current), String(settings.mode || "sequential"))
    if (name !== "")
      stateFile.setText(root.directory + "/" + name + "\n")
  }

  FolderListModel {
    id: folder
    folder: root.directory !== "" ? "file://" + root.directory : ""
    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.avif"]
    showDirs: false
  }

  WatchedFile {
    id: stateFile
    path: root.statePath
  }

  WidgetTimer {
    widget: root
    timerName: "rotate"
    running: root.active && root.images.length > 1
    repeat: true
    onTriggered: root.rotate()
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.wallpaper
    color: root.active ? Theme.subtext : Theme.muted
    tooltip: (root.current !== "" ? Model.fileName(root.current) : "Wallpaper") + (root.active ? "" : " (paused on battery)")
      + " · " + root.images.length + " images, click for the next"
    onClicked: root.rotate()
  }

  IpcHandler {
    target: "subcult.wallpaper"
    function next(): void { root.rotate() }
  }
}
