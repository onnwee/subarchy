import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Rotates the wallpaper on a schedule (stage 3, off by default: add
// "subcult.auto-wallpaper" to the bar layout). The Wallpaper service holds
// the schedule and does the rotating, once however many bars show this
// widget; on battery it waits unless `onBattery` is set. Click goes to the
// next image now. Settings: directory (the images), mode (sequential or
// shuffle), onBattery.
BarWidget {
  id: root

  implicitWidth: button.implicitWidth

  onSettingsChanged: Wallpaper.configure(settings)
  Component.onCompleted: Wallpaper.acquire(settings)
  Component.onDestruction: Wallpaper.release()

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.wallpaper
    color: Wallpaper.active ? Theme.subtext : Theme.muted
    tooltip: (Wallpaper.current !== "" ? Model.fileName(Wallpaper.current) : "Wallpaper") + (Wallpaper.active ? "" : " (paused on battery)")
      + " · " + Wallpaper.images.length + " images, click for the next"
    onClicked: Wallpaper.rotate()
  }
}
