pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ConfigModel.js" as ConfigModel

// The bar's layered config (ADR 0048): system defaults under the user's
// file, which is watched even before it exists. A broken user file logs
// one warning and the defaults stay in use.
Singleton {
  id: root

  readonly property string systemPath: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/shell/bar.json"
  readonly property string userPath: Quickshell.env("HOME") + "/.config/subcult/shell/bar.json"

  property var defaults: ({})
  property string lastWarning: ""
  readonly property var parsed: ConfigModel.parse(userFile.text, defaults)
  // The user's file as written, for the settings panel's own merge.
  readonly property string userText: userFile.text
  readonly property var bar: parsed.config

  onParsedChanged: {
    if (parsed.warning !== "" && parsed.warning !== lastWarning)
      console.warn("subcult shell config:", userPath + ":", parsed.warning)
    lastWarning = parsed.warning
  }

  // Writes one setting of one widget into the user's file, leaving
  // everything else as it is (the scoped write of ADR 0068). The new
  // config applies at once; the file watch catches up after.
  function set(widgetId, key, value) {
    let user = {}
    try {
      const t = userFile.text
      user = t && t.trim() !== "" ? JSON.parse(t) : {}
    } catch (e) {
      console.warn("subcult shell config: not saving over a broken", userPath)
      return false
    }
    userFile.setText(JSON.stringify(ConfigModel.withWidgetSetting(user, widgetId, key, value), null, 2) + "\n")
    return true
  }

  FileView {
    path: root.systemPath
    blockLoading: true
    onLoaded: {
      try {
        root.defaults = JSON.parse(text())
      } catch (e) {
        console.warn("subcult shell config: system defaults are broken:", e.message)
      }
    }
  }

  WatchedFile {
    id: userFile
    path: root.userPath
  }
}
