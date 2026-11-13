import QtQuick
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Media downloads with yt-dlp (stage 3, off by default: add
// "subcult.downloads" to the bar layout). The bar shows the running
// download's percentage and the queue count; a click opens the panel, where
// a URL is pasted. The widget stays in the bar when idle so the panel can
// take the first URL. The Downloads service runs one yt-dlp at a time and
// nothing while the queue is empty.
BarWidget {
  id: root

  readonly property var jobs: Downloads.jobs
  readonly property var running: jobs.find(j => j.status === "running") || null
  readonly property int queued: jobs.filter(j => j.status === "queued").length

  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.download
    label: root.running ? Math.round(root.running.percent) + "%" + (root.queued > 0 ? " +" + root.queued : "") : (root.queued > 0 ? "+" + root.queued : "")
    color: Theme.subtext
    tooltip: root.running ? Model.fileName(root.running.title || root.running.url) + (root.running.speed ? " · " + root.running.speed : "") : (root.queued > 0 ? "Downloads queued: " + root.queued : "Downloads")
    onClicked: root.openPanel()
  }
}
