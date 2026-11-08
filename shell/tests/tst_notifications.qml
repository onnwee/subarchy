import QtQuick
import QtTest

import "../services/NotificationsModel.js" as Model

TestCase {
  name: "Notifications"

  function entry(i, urgency) {
    return { id: i, appName: "app", summary: "s" + i, body: "", urgency: urgency || "normal", time: i, read: false }
  }

  function test_removeRecord() {
    const h = [entry(1), entry(2), entry(3)]
    compare(Model.removeRecord(h, 2).map(e => e.id), [1, 3])
    compare(Model.removeRecord(h, 9).length, 3)
    compare(h.length, 3, "does not mutate")
    compare(Model.removeRecord(null, 1), [])
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

  function test_plain() {
    compare(Model.plain("a &amp; <b>b</b>", 100), "a & b")
    compare(Model.plain("&lt;tag&gt; &quot;q&quot; &#39;s&#39; &#65;&#x42;", 100), "<tag> \"q\" 's' AB")
    compare(Model.plain("  many \n\n   spaces\tand <br/> breaks ", 100), "many spaces and breaks")
    compare(Model.plain("<a href=\"x\">link</a><img src='y'/>", 100), "link")
    compare(Model.plain("&amp;lt;", 100), "&lt;", "entities decode once")
    compare(Model.plain(null, 10), "")
    compare(Model.plain(12, 10), "12")
  }

  function test_plainCaps() {
    compare(Model.plain("x".repeat(300), 200).length, 200, "summary cap")
    compare(Model.plain("x".repeat(3000), 2000).length, 2000, "body cap")
    compare(Model.plain("x".repeat(100), 64).length, 64, "app name cap")
    compare(Model.plain("short", 64), "short")
  }

  function test_timeoutMs() {
    compare(Model.timeoutMs(5000, "critical"), 0, "critical stays")
    compare(Model.timeoutMs(-1, "normal"), 5000, "the app's default")
    compare(Model.timeoutMs(0, "normal"), 5000)
    compare(Model.timeoutMs(500, "normal"), 2000, "too short to read")
    compare(Model.timeoutMs(600000, "low"), 30000, "too long to keep")
    compare(Model.timeoutMs(8000, "normal"), 8000)
  }

  function test_updateRecord() {
    const h = [entry(2), entry(1)]
    const next = Model.updateRecord(h, 1, { summary: "new", body: "b" })
    compare(next.map(e => e.summary), ["s2", "new"])
    compare(next[1].body, "b")
    compare(next[1].read, false)
    compare(h[1].summary, "s1", "the input is not changed")
    compare(Model.updateRecord(h, 9, { summary: "x" }).map(e => e.summary), ["s2", "s1"], "an unknown id changes nothing")
  }

  function test_restore() {
    compare(Model.restore('[{"id":1,"summary":"a","read":true}]', 100).length, 1)
    compare(Model.restore("broken", 100), [])
    compare(Model.restore('{"not":"a list"}', 100), [])
  }
}
