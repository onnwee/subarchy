.pragma library
// The calendar widget's data (ADR 0061, issue #90): events from the sync
// cache ~/.local/state/subcult/calendar/events.json that `subcult calendar
// sync` writes, the next one for the bar, and a month grid with each day's
// events for the panel. Times are the machine's local time.

const DAY = 86400000

// The cache's events, sorted by start, with Date objects; anything that is
// not the cache is no events.
function events(text) {
  let d
  try {
    d = JSON.parse(text)
  } catch (e) {
    return []
  }
  if (!d || !Array.isArray(d.events))
    return []
  const out = []
  for (const e of d.events) {
    if (!e || typeof e.title !== "string")
      continue
    const start = new Date(e.start)
    const end = new Date(e.end)
    if (isNaN(start.getTime()))
      continue
    out.push({ id: String(e.id || ""), calendar: String(e.calendar || ""), title: e.title, start: start,
      end: isNaN(end.getTime()) ? start : end, allDay: !!e.allDay, location: String(e.location || "") })
  }
  out.sort((a, b) => a.start - b.start || a.title.localeCompare(b.title))
  return out
}

// When the cache was written, or null.
function syncedAt(text) {
  try {
    const d = JSON.parse(text)
    const t = new Date(d.syncedAt)
    return isNaN(t.getTime()) ? null : t
  } catch (e) {
    return null
  }
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

// The next event: the first timed one that has not ended, or an all-day one
// today or later; null when there is none.
function next(list, now) {
  for (const e of list) {
    if (e.allDay) {
      if (startOfDay(e.end) > startOfDay(now) || sameDay(e.start, now) || (e.start <= now && e.end > now))
        return e
    } else if (e.end > now) {
      return e
    }
  }
  return null
}

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

function hm(d) {
  return pad(d.getHours()) + ":" + pad(d.getMinutes())
}

// The bar's label for the next event: "Standup 14:00", "Standup now" while
// it runs, "Tomorrow Dentist 09:00", "Sat Trip" for a later all-day event.
function label(e, now) {
  if (!e)
    return ""
  const title = e.title.length > 32 ? e.title.slice(0, 31) + "…" : e.title
  const days = Math.round((startOfDay(e.start) - startOfDay(now)) / DAY)
  const dayWord = days <= 0 ? "" : days === 1 ? "Tomorrow " : Qt.formatDate(e.start, "ddd") + " "
  if (e.allDay)
    return days <= 0 ? title + " today" : dayWord + title
  if (e.start <= now && e.end > now)
    return title + " now"
  return dayWord + title + " " + hm(e.start)
}

// The events on a day, in order.
function onDay(list, day) {
  return list.filter(e => e.allDay ? startOfDay(e.start) <= startOfDay(day) && (startOfDay(e.end) > startOfDay(day) || sameDay(e.start, day))
    : sameDay(e.start, day))
}

// Six weeks of cells for the month of `month` (a Date): each cell is
// { date, inMonth, today, count }. The week starts on firstDay (0 Sunday,
// 1 Monday).
function grid(month, now, list, firstDay) {
  const first = new Date(month.getFullYear(), month.getMonth(), 1)
  const lead = (first.getDay() - firstDay + 7) % 7
  const start = new Date(first.getFullYear(), first.getMonth(), 1 - lead)
  const cells = []
  for (let i = 0; i < 42; i++) {
    const date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
    cells.push({ date: date, inMonth: date.getMonth() === month.getMonth(), today: sameDay(date, now), count: onDay(list, date).length })
  }
  return cells
}

// Weekday initials from firstDay.
function weekdays(firstDay) {
  const names = ["S", "M", "T", "W", "T", "F", "S"]
  return names.slice(firstDay).concat(names.slice(0, firstDay))
}

// An event's line in the day list: "14:00–15:00 Standup" or "All day Trip".
function line(e) {
  if (e.allDay)
    return "All day  " + e.title
  return hm(e.start) + "–" + hm(e.end) + "  " + e.title
}

function shiftMonth(month, by) {
  return new Date(month.getFullYear(), month.getMonth() + by, 1)
}
