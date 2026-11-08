// Package calendar syncs CalDAV and iCal sources into a cache the shell's
// calendar widget reads (ADR 0061, plan 3). Credentials come from the
// keyring, never from the config; the cache is plain JSON.
package calendar

import (
	"bufio"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Event is one occurrence in the cache. Times are RFC 3339 in the local
// zone; all-day events carry dates with a 00:00 time and AllDay set.
type Event struct {
	ID       string    `json:"id"`
	Calendar string    `json:"calendar"`
	Title    string    `json:"title"`
	Start    time.Time `json:"start"`
	End      time.Time `json:"end"`
	AllDay   bool      `json:"allDay"`
	Location string    `json:"location,omitempty"`
	URL      string    `json:"url,omitempty"`
}

// Window is the span of occurrences the cache keeps.
type Window struct {
	From, To time.Time
}

// DefaultWindow is yesterday to thirty days out.
func DefaultWindow(now time.Time) Window {
	day := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	return Window{From: day.AddDate(0, 0, -1), To: day.AddDate(0, 0, 31)}
}

type property struct {
	name   string
	params map[string]string
	value  string
}

// unfold joins iCalendar's continuation lines (a line starting with a
// space or tab continues the previous one).
func unfold(text string) []string {
	var lines []string
	sc := bufio.NewScanner(strings.NewReader(text))
	sc.Buffer(make([]byte, 1024*1024), 16*1024*1024)
	for sc.Scan() {
		l := strings.TrimRight(sc.Text(), "\r")
		if (strings.HasPrefix(l, " ") || strings.HasPrefix(l, "\t")) && len(lines) > 0 {
			lines[len(lines)-1] += l[1:]
			continue
		}
		lines = append(lines, l)
	}
	return lines
}

func parseProperty(line string) (property, bool) {
	colon := -1
	inQuote := false
	for i, c := range line {
		switch {
		case c == '"':
			inQuote = !inQuote
		case c == ':' && !inQuote:
			colon = i
		}
		if colon >= 0 {
			break
		}
	}
	if colon <= 0 {
		return property{}, false
	}
	head, value := line[:colon], line[colon+1:]
	parts := strings.Split(head, ";")
	p := property{name: strings.ToUpper(parts[0]), params: map[string]string{}, value: value}
	for _, kv := range parts[1:] {
		k, v, ok := strings.Cut(kv, "=")
		if ok {
			p.params[strings.ToUpper(k)] = strings.Trim(v, "\"")
		}
	}
	return p, true
}

// unescape undoes iCalendar text escapes.
func unescape(s string) string {
	return strings.NewReplacer(`\n`, "\n", `\N`, "\n", `\,`, ",", `\;`, ";", `\\`, `\`).Replace(s)
}

// parseTime reads a DATE or DATE-TIME value: floating times are local,
// Z is UTC, TZID names a zone (unknown zones fall back to local).
func parseTime(p property, loc *time.Location) (time.Time, bool, error) {
	v := strings.TrimSpace(p.value)
	if p.params["VALUE"] == "DATE" || (len(v) == 8 && !strings.Contains(v, "T")) {
		t, err := time.ParseInLocation("20060102", v, loc)
		return t, true, err
	}
	zone := loc
	if tz := p.params["TZID"]; tz != "" {
		if l, err := time.LoadLocation(tz); err == nil {
			zone = l
		}
	}
	if strings.HasSuffix(v, "Z") {
		t, err := time.Parse("20060102T150405Z", v)
		return t.In(loc), false, err
	}
	t, err := time.ParseInLocation("20060102T150405", v, zone)
	return t.In(loc), false, err
}

type vevent struct {
	uid, summary, location, url string
	start, end                  time.Time
	allDay                      bool
	rrule                       string
	exdates                     map[string]bool
	recurrenceID                time.Time // the occurrence this VEVENT replaces
}

// parseICS reads every VEVENT of an iCalendar text.
func parseICS(text string, loc *time.Location) ([]vevent, error) {
	var events []vevent
	var cur *vevent
	for _, line := range unfold(text) {
		p, ok := parseProperty(line)
		if !ok {
			continue
		}
		switch {
		case p.name == "BEGIN" && strings.EqualFold(p.value, "VEVENT"):
			cur = &vevent{exdates: map[string]bool{}}
		case p.name == "END" && strings.EqualFold(p.value, "VEVENT"):
			if cur != nil && cur.uid != "" && !cur.start.IsZero() {
				if cur.end.IsZero() {
					if cur.allDay {
						cur.end = cur.start.AddDate(0, 0, 1)
					} else {
						cur.end = cur.start
					}
				}
				events = append(events, *cur)
			}
			cur = nil
		case cur == nil:
		case p.name == "UID":
			cur.uid = p.value
		case p.name == "SUMMARY":
			cur.summary = unescape(p.value)
		case p.name == "LOCATION":
			cur.location = unescape(p.value)
		case p.name == "URL":
			cur.url = p.value
		case p.name == "RRULE":
			cur.rrule = p.value
		case p.name == "RECURRENCE-ID":
			if t, _, err := parseTime(p, loc); err == nil {
				cur.recurrenceID = t
			}
		case p.name == "EXDATE":
			for _, v := range strings.Split(p.value, ",") {
				t, _, err := parseTime(property{name: "EXDATE", params: p.params, value: v}, loc)
				if err == nil {
					cur.exdates[t.Format(time.RFC3339)] = true
				}
			}
		case p.name == "DTSTART":
			t, allDay, err := parseTime(p, loc)
			if err != nil {
				return nil, fmt.Errorf("DTSTART %q: %w", p.value, err)
			}
			cur.start, cur.allDay = t, allDay
		case p.name == "DTEND":
			t, _, err := parseTime(p, loc)
			if err != nil {
				return nil, fmt.Errorf("DTEND %q: %w", p.value, err)
			}
			cur.end = t
		case p.name == "DURATION" && cur.end.IsZero():
			if d, ok := parseDuration(p.value); ok {
				cur.end = cur.start.Add(d)
			}
		}
	}
	return events, nil
}

// parseDuration reads an iCalendar duration such as PT1H30M or P1D.
func parseDuration(s string) (time.Duration, bool) {
	s = strings.TrimPrefix(s, "+")
	neg := strings.HasPrefix(s, "-")
	s = strings.TrimPrefix(s, "-")
	if !strings.HasPrefix(s, "P") {
		return 0, false
	}
	var d time.Duration
	num := ""
	inTime := false
	for _, c := range s[1:] {
		switch {
		case c >= '0' && c <= '9':
			num += string(c)
		case c == 'T':
			inTime = true
		default:
			n, err := strconv.Atoi(num)
			if err != nil {
				return 0, false
			}
			num = ""
			switch {
			case c == 'W':
				d += time.Duration(n) * 7 * 24 * time.Hour
			case c == 'D':
				d += time.Duration(n) * 24 * time.Hour
			case c == 'H' && inTime:
				d += time.Duration(n) * time.Hour
			case c == 'M' && inTime:
				d += time.Duration(n) * time.Minute
			case c == 'S' && inTime:
				d += time.Duration(n) * time.Second
			default:
				return 0, false
			}
		}
	}
	if neg {
		d = -d
	}
	return d, true
}

// Occurrences expands the events into the window: single events as they
// are, recurring ones by their RRULE (daily, weekly with BYDAY, monthly by
// day of month, yearly; INTERVAL, COUNT, UNTIL, EXDATE). Overridden
// occurrences (RECURRENCE-ID) replace the generated one.
func Occurrences(calendar string, events []vevent, w Window) []Event {
	overrides := map[string]bool{}
	for _, e := range events {
		if !e.recurrenceID.IsZero() {
			overrides[e.uid+"@"+e.recurrenceID.UTC().Format(time.RFC3339)] = true
		}
	}
	var out []Event
	for _, e := range events {
		dur := e.end.Sub(e.start)
		add := func(start time.Time) {
			if start.Before(w.To) && start.Add(dur).After(w.From) {
				out = append(out, Event{
					ID: e.uid + "@" + start.Format(time.RFC3339), Calendar: calendar, Title: e.summary,
					Start: start, End: start.Add(dur), AllDay: e.allDay, Location: e.location, URL: e.url,
				})
			}
		}
		if e.rrule == "" {
			add(e.start)
			continue
		}
		for _, start := range expand(e, w) {
			if e.exdates[start.Format(time.RFC3339)] || overrides[e.uid+"@"+start.UTC().Format(time.RFC3339)] {
				continue
			}
			add(start)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Start.Equal(out[j].Start) {
			return out[i].ID < out[j].ID
		}
		return out[i].Start.Before(out[j].Start)
	})
	return out
}

var weekdays = map[string]time.Weekday{"SU": time.Sunday, "MO": time.Monday, "TU": time.Tuesday, "WE": time.Wednesday, "TH": time.Thursday, "FR": time.Friday, "SA": time.Saturday}

// expand lists a recurring event's starts up to the window's end, capped
// at 1000 occurrences.
func expand(e vevent, w Window) []time.Time {
	rule := map[string]string{}
	for _, kv := range strings.Split(e.rrule, ";") {
		if k, v, ok := strings.Cut(kv, "="); ok {
			rule[strings.ToUpper(k)] = strings.ToUpper(v)
		}
	}
	interval := 1
	if n, err := strconv.Atoi(rule["INTERVAL"]); err == nil && n > 0 {
		interval = n
	}
	count := -1
	if n, err := strconv.Atoi(rule["COUNT"]); err == nil {
		count = n
	}
	until := w.To
	if u := rule["UNTIL"]; u != "" {
		if t, _, err := parseTime(property{name: "UNTIL", params: map[string]string{}, value: u}, e.start.Location()); err == nil && t.Before(until) {
			until = t.Add(time.Second)
		}
	}
	var days []time.Weekday
	for _, d := range strings.Split(rule["BYDAY"], ",") {
		if wd, ok := weekdays[strings.TrimLeft(d, "+-0123456789")]; ok && d != "" {
			days = append(days, wd)
		}
	}
	var starts []time.Time
	emit := func(t time.Time) bool {
		if count >= 0 && len(starts) >= count {
			return false
		}
		if !t.Before(until) {
			return false
		}
		starts = append(starts, t)
		return len(starts) < 1000
	}
	switch rule["FREQ"] {
	case "DAILY":
		for t := e.start; emit(t); t = t.AddDate(0, 0, interval) {
		}
	case "WEEKLY":
		if len(days) == 0 {
			days = []time.Weekday{e.start.Weekday()}
		}
		weekStart := e.start.AddDate(0, 0, -int(e.start.Weekday()))
		for week := weekStart; ; week = week.AddDate(0, 0, 7*interval) {
			done := false
			for d := 0; d < 7; d++ {
				t := week.AddDate(0, 0, d)
				if t.Before(e.start) {
					continue
				}
				for _, wd := range days {
					if t.Weekday() == wd {
						if !emit(t) {
							done = true
						}
					}
				}
				if done {
					break
				}
			}
			if done || week.After(until) {
				break
			}
		}
	case "MONTHLY":
		for t := e.start; emit(t); t = e.start.AddDate(0, interval*(len(starts)), 0) {
		}
	case "YEARLY":
		for t := e.start; emit(t); t = e.start.AddDate(interval*len(starts), 0, 0) {
		}
	default:
		starts = append(starts, e.start)
	}
	return starts
}
