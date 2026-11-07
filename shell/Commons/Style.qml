pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Sizes and fonts. The fonts follow the fontconfig roles: the family names
// are resolved with fc-match and resolved again when the user's role file
// changes (`subcult font set`), so the shell repaints in the new font.
Singleton {
  id: root

  readonly property int barHeight: 26
  readonly property int iconSize: 14
  readonly property int fontSize: 11
  readonly property int spacing: 8
  readonly property int padding: 6

  property string fontFamily: "monospace"
  property string uiFontFamily: "sans-serif"

  function resolve() {
    monoQuery.running = true
    uiQuery.running = true
  }

  Process {
    id: monoQuery
    command: ["fc-match", "-f", "%{family[0]}", "monospace"]
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.fontFamily = text.trim()
    }
  }

  Process {
    id: uiQuery
    command: ["fc-match", "-f", "%{family[0]}", "sans-serif"]
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.uiFontFamily = text.trim()
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/subcult/fonts.conf"
    watchChanges: true
    printErrors: false
    onFileChanged: root.resolve()
  }

  Component.onCompleted: resolve()
}
