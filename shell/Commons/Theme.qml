pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ThemeModel.js" as ThemeModel

// Colour tokens from the palette (ADR 0037). The system palette is the
// fallback for every role; the user's palette (Theme Tender writes it) is
// watched, even before it exists, so a theme change repaints without a
// restart and rebuilds the cursor in the new colours.
Singleton {
  id: root

  readonly property string systemPath: (Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult") + "/default/theme/palette.json"
  readonly property string userPath: Quickshell.env("HOME") + "/.config/subcult/theme/palette.json"

  property var fallback: ({})
  property var user: ({})
  readonly property var tokens: ThemeModel.tokens(user, fallback)

  readonly property color base: tokens.base || "#100B19"
  readonly property color mantle: tokens.mantle || "#0B0812"
  readonly property color crust: tokens.crust || "#06040A"
  readonly property color surface: tokens.surface || "#1F1830"
  readonly property color text: tokens.text || "#F0ECE4"
  readonly property color subtext: tokens.subtext || "#9A92A8"
  readonly property color muted: tokens.muted || "#5E5570"
  readonly property color accent: tokens.accent || "#00FF88"
  readonly property color border: tokens.border || "#8F4BC8"
  readonly property color borderInactive: tokens.borderInactive || "#1F1830"
  readonly property color selection: tokens.selection || "#3B2470"
  readonly property color warning: tokens.warning || "#F6D447"
  readonly property color error: tokens.error || "#D52032"

  function colorsOf(text) {
    if (text.trim() === "")
      return {}
    try {
      const doc = JSON.parse(text)
      return doc && typeof doc.colors === "object" && doc.colors !== null ? doc.colors : {}
    } catch (e) {
      console.warn("subcult theme: palette is not valid JSON:", e.message)
      return {}
    }
  }

  FileView {
    path: root.systemPath
    blockLoading: true
    onLoaded: root.fallback = root.colorsOf(text())
  }

  WatchedFile {
    path: root.userPath
    onChanged: (live) => {
      root.user = root.colorsOf(text)
      if (live)
        Quickshell.execDetached(["subcult", "cursor", "apply"])
    }
  }
}
