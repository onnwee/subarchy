pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import "../widgets/auto-wallpaper/Model.js" as Model

// Wallpaper rotation behind the auto-wallpaper widget. A docked laptop has
// two full bars, so the schedule, the rotation and the `subcult.wallpaper`
// IPC target live here, once: each widget acquires the service with its
// settings and releases it when it goes, and the schedule runs while one
// holds it. The interval is the manifest's "rotate" timer (ADR 0068) and
// follows Power; on battery it waits unless `onBattery` is set. The chosen
// image's path goes to ~/.local/state/subcult/wallpaper, which the
// background watches.
Singleton {
  id: root

  property int users: 0
  property var settings: ({})
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/wallpaper"
  readonly property string directory: root.users > 0 ? String(root.settings.directory || "") : ""
  readonly property var images: {
    const names = []
    for (let i = 0; i < folder.count; i++)
      names.push(folder.get(i, "fileName"))
    return Model.images(names)
  }
  readonly property string current: stateFile.text.trim()
  readonly property bool active: Model.active(Power.onBattery, root.settings.onBattery === true)

  // What every output's background shows: the chosen image, else the
  // default once the subarchy-wallpapers package has installed it.
  // `readable` comes from one `test -r` for all outputs, run again when
  // the path changes.
  readonly property string defaultImage: "/usr/share/backgrounds/subarchy/01-acid-negative-space.png"
  readonly property string image: root.current !== "" ? root.current : root.defaultImage
  property bool readable: false
  onImageChanged: check.start()

  function acquire(settings) {
    root.settings = settings || {}
    if (root.users++ === 0)
      Power.register(schedule)
  }

  function release() {
    root.users = Math.max(0, root.users - 1)
    if (root.users === 0)
      Power.unregister(schedule)
  }

  function configure(settings) {
    root.settings = settings || {}
  }

  function rotate() {
    if (root.users === 0)
      return
    const name = Model.next(root.images, Model.fileName(root.current), String(root.settings.mode || "sequential"))
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

  // The command is set when the check starts, not bound; a path that
  // changed while a check ran is checked again when it ends.
  Process {
    id: check
    function start() {
      if (check.running)
        return
      check.command = ["test", "-r", root.image]
      check.running = true
    }
    onExited: (code) => {
      if (check.command[2] !== root.image)
        Qt.callLater(check.start)
      else
        root.readable = code === 0
    }
    Component.onCompleted: check.start()
  }

  // The widget's "rotate" timer, reported through Power like a WidgetTimer.
  Timer {
    id: schedule
    readonly property string widgetId: "subcult.auto-wallpaper"
    readonly property string timerName: "rotate"
    readonly property var entry: WidgetIndex.entry(widgetId)
    interval: entry ? Power.interval(entry.manifest, timerName) : 0
    running: root.users > 0 && root.active && root.images.length > 1 && interval > 0
    repeat: true
    onTriggered: root.rotate()
  }

  IpcHandler {
    target: "subcult.wallpaper"
    function next(): void { root.rotate() }
  }
}
