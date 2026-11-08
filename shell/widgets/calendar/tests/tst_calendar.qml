import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Calendar"

  // Saturday 2026-11-07 10:00 local time.
  readonly property date now: new Date(2026, 10, 7, 10, 0)
  readonly property string cache: JSON.stringify({ version: 1, syncedAt: "2026-11-07T09:30:00Z", events: [
    { id: "b", calendar: "Work", title: "Standup", start: "2026-11-07T14:00:00", end: "2026-11-07T14:15:00", allDay: false },
    { id: "a", calendar: "Home", title: "Dentist", start: "2026-11-08T09:00:00", end: "2026-11-08T10:00:00", allDay: false, location: "Main St" },
    { id: "c", calendar: "Home", title: "Trip", start: "2026-11-10T00:00:00", end: "2026-11-12T00:00:00", allDay: true },
    { id: "d", calendar: "Work", title: "Earlier", start: "2026-11-07T08:00:00", end: "2026-11-07T09:00:00", allDay: false },
    { id: "bad", title: "No start", start: "nope", end: "nope" },
    null
  ] })
  readonly property var list: Model.events(cache)

  function test_events() {
    compare(list.map(e => e.title), ["Earlier", "Standup", "Dentist", "Trip"], "sorted by start, the broken one dropped")
    compare(list[2].location, "Main St")
    compare(list[3].allDay, true)
    compare(Model.events("not json"), [])
    compare(Model.events("{}"), [])
    compare(Model.syncedAt(cache).getTime(), new Date("2026-11-07T09:30:00Z").getTime())
    compare(Model.syncedAt("x"), null)
  }

  function test_next() {
    compare(Model.next(list, now).title, "Standup", "the earlier event has ended")
    compare(Model.next(list, new Date(2026, 10, 7, 14, 5)).title, "Standup", "running counts")
    compare(Model.next(list, new Date(2026, 10, 7, 14, 20)).title, "Dentist")
    compare(Model.next(list, new Date(2026, 10, 9, 12, 0)).title, "Trip", "a coming all-day event")
    compare(Model.next(list, new Date(2026, 10, 11, 12, 0)).title, "Trip", "an all-day event still running")
    compare(Model.next(list, new Date(2026, 10, 12, 12, 0)), null, "nothing after the trip")
    compare(Model.next([], now), null)
  }

  function test_label() {
    compare(Model.label(Model.next(list, now), now), "Standup 14:00")
    compare(Model.label(list[1], new Date(2026, 10, 7, 14, 5)), "Standup now")
    compare(Model.label(list[2], now), "Tomorrow Dentist 09:00")
    compare(Model.label(list[3], now), "Tue Trip")
    compare(Model.label(list[3], new Date(2026, 10, 10, 12, 0)), "Trip today")
    compare(Model.label(null, now), "")
    const long = { title: "A very long meeting title that goes on and on", start: new Date(2026, 10, 7, 15, 0), end: new Date(2026, 10, 7, 16, 0), allDay: false }
    verify(Model.label(long, now).length <= 32 + 7)
  }

  function test_onDayAndLine() {
    compare(Model.onDay(list, now).map(e => e.title), ["Earlier", "Standup"])
    compare(Model.onDay(list, new Date(2026, 10, 11)).map(e => e.title), ["Trip"], "an all-day span covers its days")
    compare(Model.onDay(list, new Date(2026, 10, 12)).length, 0, "the end day is exclusive")
    compare(Model.line(list[1]), "14:00–14:15  Standup")
    compare(Model.line(list[3]), "All day  Trip")
  }

  function test_grid() {
    const cells = Model.grid(new Date(2026, 10, 1), now, list, 1)
    compare(cells.length, 42)
    compare(cells[0].date.getDate(), 26, "November 2026 starts on a Sunday; the Monday grid begins Oct 26")
    compare(cells[0].inMonth, false)
    compare(cells[6].date.getDate(), 1)
    compare(cells.filter(c => c.today).length, 1)
    compare(cells.find(c => c.today).date.getDate(), 7)
    compare(cells.find(c => c.inMonth && c.date.getDate() === 7).count, 2)
    compare(cells.find(c => c.inMonth && c.date.getDate() === 11).count, 1)
    compare(Model.weekdays(1).join(""), "MTWTFSS")
    compare(Model.weekdays(0).join(""), "SMTWTFS")
    compare(Model.shiftMonth(new Date(2026, 11, 1), 1).getFullYear(), 2027)
  }
}
