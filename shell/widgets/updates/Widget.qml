import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Available package updates, from the count `subcult update check` writes
// once a day. Watched, not polled; hidden at zero. Click runs the update in
// a terminal.
BarWidget {
  id: root

  readonly property int count: Model.count(file.text)

  hidden: Model.hidden(count)
  implicitWidth: button.implicitWidth

  WatchedFile {
    id: file
    path: Quickshell.env("HOME") + "/.local/state/subcult/update-count"
  }

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.updates
    label: String(root.count)
    color: Theme.accent
    tooltip: root.count + (root.count === 1 ? " update" : " updates")
    // Through uwsm-app (ADR 0031): the update runs in its own unit and
    // survives a shell restart.
    onClicked: Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "subcult", "update"])
  }
}
