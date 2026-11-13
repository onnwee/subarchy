pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Commons
import "NotificationsModel.js" as Model

// The notification daemon (org.freedesktop.Notifications). Live
// notifications pop up; plain records go to a history of 100, saved to
// $XDG_STATE_HOME/subcult/notifications.json (default ~/.local/state).
// Do-not-disturb holds back popups except critical ones. Text is stored
// and shown as capped plain text only (no markup, no images): bodies and
// summaries come from any app or web page.
//
// Each popup has an entry here that owns its timer: the app's timeout
// (within 2..30 s, 5 s by default, critical ones stay), paused while the
// pointer is over the card, restarted when the app replaces the
// notification (replaces_id), which also updates its history record.
Singleton {
  id: root

  readonly property int cap: 100
  readonly property int summaryCap: 200
  readonly property int bodyCap: 2000
  readonly property int appNameCap: 64
  readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/subcult/notifications.json"

  property bool dnd: false
  property var history: []
  property var popups: []
  // Popup entries by notification id.
  property var entries: ({})
  readonly property int unread: Model.unread(history)

  component Entry: QtObject {
    id: entry
    required property var n
    property real due: 0 // epoch ms when it expires; 0 while it stays
    property int remaining: 0 // ms left while paused

    signal expired(var n)

    readonly property Timer timer: Timer {
      repeat: false
      onTriggered: entry.expired(entry.n)
    }

    function arm(ms) {
      if (ms <= 0) {
        entry.timer.stop()
        entry.due = 0
        return
      }
      entry.due = Date.now() + ms
      entry.timer.interval = ms
      entry.timer.restart()
    }

    function pause() {
      if (entry.due > 0 && entry.timer.running) {
        entry.remaining = Math.max(1000, entry.due - Date.now())
        entry.timer.stop()
      }
    }

    function resume() {
      if (entry.due > 0 && !entry.timer.running)
        entry.arm(entry.remaining)
    }
  }

  Component {
    id: entryComponent
    Entry {}
  }

  function urgencyName(u) {
    return u === NotificationUrgency.Critical ? "critical" : u === NotificationUrgency.Low ? "low" : "normal"
  }

  function timeoutFor(n) {
    return Model.timeoutMs(n.expireTimeout, root.urgencyName(n.urgency))
  }

  function record(n) {
    return {
      appName: Model.plain(n.appName, root.appNameCap),
      summary: Model.plain(n.summary, root.summaryCap),
      body: Model.plain(n.body, root.bodyCap),
      urgency: root.urgencyName(n.urgency)
    }
  }

  // The popup is gone: forget its entry.
  function drop(n) {
    root.popups = root.popups.filter(p => p !== n)
    const e = root.entries[n.id]
    if (e) {
      e.timer.stop()
      const next = Object.assign({}, root.entries)
      delete next[n.id]
      root.entries = next
      e.destroy()
    }
  }

  function dismiss(n) {
    root.drop(n)
    if (n && n.tracked)
      n.dismiss()
  }

  // Off screen: the app hears the notification expired, and it stops
  // being tracked (its record stays in the history).
  function expire(n) {
    const shown = root.popups.indexOf(n) >= 0
    root.drop(n)
    if (n && (shown || n.tracked))
      n.expire()
  }

  // The pointer is over the card: its timer waits.
  function hold(n) {
    const e = root.entries[n.id]
    if (e)
      e.pause()
  }

  function release(n) {
    const e = root.entries[n.id]
    if (e)
      e.resume()
  }

  // The app replaced the notification: new text in the popup (it binds to
  // the live object) and the history, and the timer starts over.
  function replaced(n) {
    root.history = Model.updateRecord(root.history, n.id, root.record(n))
    root.save()
    const e = root.entries[n.id]
    if (e)
      e.arm(root.timeoutFor(n))
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

  function removeRecord(id, time) {
    root.history = Model.removeRecord(root.history, id, time)
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
      const rec = Object.assign({ id: n.id, time: Date.now(), read: false }, root.record(n))
      root.history = Model.push(root.history, rec, root.cap)
      root.save()
      n.closed.connect(() => root.drop(n))
      n.summaryChanged.connect(() => root.replaced(n))
      n.bodyChanged.connect(() => root.replaced(n))
      if (Model.shouldPopup(rec, root.dnd)) {
        const e = entryComponent.createObject(root, { n: n }) as Entry
        e.expired.connect(root.expire)
        root.entries = Object.assign({}, root.entries, { [n.id]: e })
        root.popups = root.popups.concat([n])
        e.arm(root.timeoutFor(n))
      } else {
        n.expire()
      }
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
