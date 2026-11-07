import QtQuick
import QtTest

import "../services/NotificationsModel.js" as Model

TestCase {
  name: "Notifications"

  function entry(i, urgency) {
    return { id: i, appName: "app", summary: "s" + i, body: "", urgency: urgency || "normal", time: i, read: false }
  }

  function test_pushNewestFirst() {
    let h = []
    h = Model.push(h, entry(1), 100)
    h = Model.push(h, entry(2), 100)
    compare(h.map(e => e.id), [2, 1])
  }

  function test_pushCaps() {
    let h = []
    for (let i = 0; i < 105; i++)
      h = Model.push(h, entry(i), 100)
    compare(h.length, 100)
    compare(h[0].id, 104)
    compare(h[99].id, 5)
  }

  function test_pushDoesNotMutate() {
    const h = [entry(1)]
    Model.push(h, entry(2), 100)
    compare(h.length, 1)
  }

  function test_dndCriticalStillPopsUp() {
    verify(Model.shouldPopup({ urgency: "normal" }, false))
    verify(!Model.shouldPopup({ urgency: "normal" }, true))
    verify(!Model.shouldPopup({ urgency: "low" }, true))
    verify(Model.shouldPopup({ urgency: "critical" }, true))
  }

  function test_unread() {
    const h = [entry(1), entry(2), Object.assign(entry(3), { read: true })]
    compare(Model.unread(h), 2)
    compare(Model.unread(Model.markAllRead(h)), 0)
    compare(Model.unread([]), 0)
  }

  function test_restore() {
    compare(Model.restore('[{"id":1,"summary":"a","read":true}]', 100).length, 1)
    compare(Model.restore("broken", 100), [])
    compare(Model.restore('{"not":"a list"}', 100), [])
  }
}
