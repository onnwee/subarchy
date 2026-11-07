pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Commons
import "NotificationsModel.js" as Model

// The notification daemon (org.freedesktop.Notifications). Live
// notifications pop up; plain records go to a history of 100, saved to
// ~/.local/state/subcult/notifications.json. Do-not-disturb holds back
// popups except critical ones.
Singleton {
  id: root

  readonly property int cap: 100
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/subcult/notifications.json"

  property bool dnd: false
  property var history: []
  property var popups: []
  readonly property int unread: Model.unread(history)

  function urgencyName(u) {
    return u === NotificationUrgency.Critical ? "critical" : u === NotificationUrgency.Low ? "low" : "normal"
  }

  function dismiss(n) {
    root.popups = root.popups.filter(p => p !== n)
    if (n)
      n.dismiss()
  }

  function expire(n) {
    root.popups = root.popups.filter(p => p !== n)
  }

  function markAllRead() {
    root.history = Model.markAllRead(root.history)
    save()
  }

  function clearHistory() {
    root.history = []
    save()
  }

  function save() {
    historyFile.setText(JSON.stringify(root.history) + "\n")
  }

  NotificationServer {
    keepOnReload: false
    actionsSupported: true
    imageSupported: true
    bodyMarkupSupported: true
    bodySupported: true

    onNotification: (n) => {
      n.tracked = true
      const record = {
        id: n.id, appName: n.appName, summary: n.summary, body: n.body,
        urgency: root.urgencyName(n.urgency), time: Date.now(), read: false
      }
      root.history = Model.push(root.history, record, root.cap)
      root.save()
      if (Model.shouldPopup(record, root.dnd))
        root.popups = root.popups.concat([n])
      n.closed.connect(() => root.expire(n))
    }
  }

  WatchedFile {
    id: historyFile
    path: root.historyPath
    onChanged: (live) => {
      if (!live)
        root.history = Model.restore(text, root.cap)
    }
  }
}
