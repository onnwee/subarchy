package calendar

import (
	"testing"
	"time"
)

func occurrencesIn(t *testing.T, ics string, from, to time.Time) []Event {
	t.Helper()
	events, err := parseICS(ics, chicago)
	if err != nil {
		t.Fatal(err)
	}
	return Occurrences("c", events, Window{From: from, To: to})
}

func day(y int, m time.Month, d int) time.Time {
	return time.Date(y, m, d, 0, 0, 0, 0, chicago)
}

func starts(events []Event) []string {
	out := make([]string, len(events))
	for i, e := range events {
		out[i] = e.Start.In(chicago).Format("2006-01-02 15:04")
	}
	return out
}

func equal(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// An alarm inside an event has properties of its own. iCloud gives its
// alarms a UID, and an email alarm has a SUMMARY.
func TestNestedComponentsDoNotOverwriteTheEvent(t *testing.T) {
	ics := "BEGIN:VEVENT\nUID:standup\nSUMMARY:Standup\nDTSTART:20260706T140000Z\nDTEND:20260706T143000Z\n" +
		"RRULE:FREQ=WEEKLY\n" +
		"BEGIN:VALARM\nUID:alarm-1\nACTION:EMAIL\nSUMMARY:Alarm notification\nDURATION:PT5M\nTRIGGER:-PT10M\nEND:VALARM\n" +
		"END:VEVENT\n" +
		"BEGIN:VEVENT\nUID:standup\nSUMMARY:Standup (moved)\nRECURRENCE-ID:20260713T140000Z\n" +
		"DTSTART:20260713T190000Z\nDTEND:20260713T193000Z\nEND:VEVENT\n"
	got := occurrencesIn(t, ics, day(2026, 7, 13), day(2026, 7, 14))
	if len(got) != 1 || got[0].Title != "Standup (moved)" || got[0].End.Sub(got[0].Start) != 30*time.Minute {
		t.Fatalf("want only the moved occurrence, 30 minutes long, got %+v", got)
	}
	first := occurrencesIn(t, ics, day(2026, 7, 6), day(2026, 7, 7))
	if len(first) != 1 || first[0].Title != "Standup" {
		t.Errorf("want the event's own title, got %+v", first)
	}
}

// A series keeps its wall-clock time in its own zone. India has no
// daylight saving, so a 19:00 Kolkata meeting is 07:30 in Chicago in
// January and 08:30 in July; a UTC series moves the same way.
func TestRecurrenceKeepsItsOwnZonesWallClock(t *testing.T) {
	ics := "BEGIN:VEVENT\nUID:india\nSUMMARY:India sync\nDTSTART;TZID=Asia/Kolkata:20260106T190000\n" +
		"DTEND;TZID=Asia/Kolkata:20260106T200000\nRRULE:FREQ=WEEKLY\nEXDATE;TZID=Asia/Kolkata:20260714T190000\nEND:VEVENT\n" +
		"BEGIN:VEVENT\nUID:utc\nSUMMARY:UTC sync\nDTSTART:20260106T150000Z\nDTEND:20260106T160000Z\nRRULE:FREQ=WEEKLY\nEND:VEVENT\n"
	january := starts(occurrencesIn(t, ics, day(2026, 1, 6), day(2026, 1, 7)))
	if want := []string{"2026-01-06 07:30", "2026-01-06 09:00"}; !equal(january, want) {
		t.Errorf("January: got %v, want %v", january, want)
	}
	july := starts(occurrencesIn(t, ics, day(2026, 7, 7), day(2026, 7, 22)))
	// July 14 is excluded for the India series.
	want := []string{"2026-07-07 08:30", "2026-07-07 10:00", "2026-07-14 10:00", "2026-07-21 08:30", "2026-07-21 10:00"}
	if !equal(july, want) {
		t.Errorf("July: got %v, want %v", july, want)
	}
}

func TestMonthlyByWeekdayAndShortMonths(t *testing.T) {
	secondTuesday := "BEGIN:VEVENT\nUID:board\nSUMMARY:Board\nDTSTART:20260113T180000\nDTEND:20260113T190000\n" +
		"RRULE:FREQ=MONTHLY;BYDAY=2TU\nEND:VEVENT\n"
	got := starts(occurrencesIn(t, secondTuesday, day(2026, 9, 1), day(2026, 12, 1)))
	if want := []string{"2026-09-08 18:00", "2026-10-13 18:00", "2026-11-10 18:00"}; !equal(got, want) {
		t.Errorf("second Tuesday: got %v, want %v", got, want)
	}
	lastFriday := "BEGIN:VEVENT\nUID:demo\nSUMMARY:Demo\nDTSTART:20260130T160000\nDTEND:20260130T170000\n" +
		"RRULE:FREQ=MONTHLY;BYDAY=-1FR\nEND:VEVENT\n"
	got = starts(occurrencesIn(t, lastFriday, day(2026, 2, 1), day(2026, 4, 1)))
	if want := []string{"2026-02-27 16:00", "2026-03-27 16:00"}; !equal(got, want) {
		t.Errorf("last Friday: got %v, want %v", got, want)
	}
	// RFC 5545: a rule that names a day a month lacks skips that month.
	thirtyFirst := "BEGIN:VEVENT\nUID:rent\nSUMMARY:Rent\nDTSTART;VALUE=DATE:20260131\nRRULE:FREQ=MONTHLY\nEND:VEVENT\n"
	got = starts(occurrencesIn(t, thirtyFirst, day(2026, 8, 30), day(2027, 1, 2)))
	if want := []string{"2026-08-31 00:00", "2026-10-31 00:00", "2026-12-31 00:00"}; !equal(got, want) {
		t.Errorf("the 31st: got %v, want %v", got, want)
	}
	leapDay := "BEGIN:VEVENT\nUID:leap\nSUMMARY:Leap\nDTSTART;VALUE=DATE:20240229\nRRULE:FREQ=YEARLY\nEND:VEVENT\n"
	got = starts(occurrencesIn(t, leapDay, day(2026, 1, 1), day(2029, 1, 1)))
	if want := []string{"2028-02-29 00:00"}; !equal(got, want) {
		t.Errorf("February 29: got %v, want %v", got, want)
	}
}

func TestMonthlyBySetPosMonthDayAndMonth(t *testing.T) {
	series := func(dtstart, rrule string) string {
		return "BEGIN:VEVENT\nUID:x\nSUMMARY:x\nDTSTART:" + dtstart + "\nRRULE:" + rrule + "\nEND:VEVENT\n"
	}
	tests := []struct {
		name, ics string
		from, to  time.Time
		want      []string
	}{
		{"last weekday of the month", series("20260130T090000", "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1"),
			day(2026, 2, 1), day(2026, 6, 1),
			[]string{"2026-02-27 09:00", "2026-03-31 09:00", "2026-04-30 09:00", "2026-05-29 09:00"}},
		{"first weekday of the month", series("20260102T090000", "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1"),
			day(2026, 2, 1), day(2026, 4, 1),
			[]string{"2026-02-02 09:00", "2026-03-02 09:00"}},
		{"the 1st and the 15th", series("20260101T120000", "FREQ=MONTHLY;BYMONTHDAY=1,15"),
			day(2026, 3, 1), day(2026, 4, 2),
			[]string{"2026-03-01 12:00", "2026-03-15 12:00", "2026-04-01 12:00"}},
		{"the last day of the month", series("20260131T120000", "FREQ=MONTHLY;BYMONTHDAY=-1"),
			day(2026, 2, 1), day(2026, 5, 1),
			[]string{"2026-02-28 12:00", "2026-03-31 12:00", "2026-04-30 12:00"}},
		{"Friday the 13th", series("20260213T120000", "FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13"),
			day(2026, 1, 1), day(2027, 1, 1),
			[]string{"2026-02-13 12:00", "2026-03-13 12:00", "2026-11-13 12:00"}},
		{"only in March and September", series("20260310T120000", "FREQ=MONTHLY;BYMONTH=3,9"),
			day(2026, 1, 1), day(2027, 4, 1),
			[]string{"2026-03-10 12:00", "2026-09-10 12:00", "2027-03-10 12:00"}},
		{"COUNT counts the kept days only", series("20260130T090000", "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=2"),
			day(2026, 1, 1), day(2026, 6, 1),
			[]string{"2026-01-30 09:00", "2026-02-27 09:00"}},
	}
	for _, tc := range tests {
		if got := starts(occurrencesIn(t, tc.ics, tc.from, tc.to)); !equal(got, tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
		}
	}
}
