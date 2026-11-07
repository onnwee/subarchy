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
// popups except critical ones. Text is shown as plain text only (no
// markup, no images): bodies and summaries come from any app or web page.
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
    if (n && n.tracked)
      n.dismiss()
  }

  // Off screen: the app hears the notification expired, and it stops
  // being tracked (its record stays in the history).
  function expire(n) {
    const shown = root.popups.indexOf(n) >= 0
    root.popups = root.popups.filter(p => p !== n)
    if (n && (shown || n.tracked))
      n.expire()
  }

  function invoke(n, action) {
    if (action)
      action.invoke()
    root.dismiss(n)
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
    imageSupported: false
    bodyMarkupSupported: false
    bodySupported: true

    onNotification: (n) => {
      n.tracked = true
      const record = {
        id: n.id, appName: n.appName, summary: n.summary, body: n.body,
        urgency: root.urgencyName(n.urgency), time: Date.now(), read: false
      }
      root.history = Model.push(root.history, record, root.cap)
      root.save()
      n.closed.connect(() => root.popups = root.popups.filter(p => p !== n))
      if (Model.shouldPopup(record, root.dnd))
        root.popups = root.popups.concat([n])
      else
        n.expire()
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
