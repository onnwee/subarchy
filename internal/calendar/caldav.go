package calendar

import (
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Fetcher gets the occurrences of a source within the cache window.
type Fetcher interface {
	Fetch(ctx context.Context, s Source, password string, w Window) ([]Event, error)
}

// HTTPFetcher reads iCal feeds with GET and CalDAV collections with a
// calendar-query REPORT limited to the window (RFC 4791), using HTTP basic
// authentication.
type HTTPFetcher struct {
	Client *http.Client
}

func (f HTTPFetcher) client() *http.Client {
	if f.Client != nil {
		return f.Client
	}
	return &http.Client{Timeout: 30 * time.Second}
}

// Fetch expands iCalendar objects into occurrences in the cache window.
func (f HTTPFetcher) Fetch(ctx context.Context, s Source, password string, w Window) ([]Event, error) {
	texts, err := f.fetchTexts(ctx, s, password, w)
	if err != nil {
		return nil, err
	}
	var events []Event
	for _, text := range texts {
		events = append(events, Occurrences(s.Name, parseICS(text, w.From.Location()), w)...)
	}
	return events, nil
}

func (f HTTPFetcher) fetchTexts(ctx context.Context, s Source, password string, w Window) ([]string, error) {
	if s.Kind == "ical" {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.URL, nil)
		if err != nil {
			return nil, err
		}
		if s.User != "" {
			req.SetBasicAuth(s.User, password)
		}
		body, err := f.do(req)
		if err != nil {
			return nil, err
		}
		return []string{string(body)}, nil
	}
	query := fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop><C:calendar-data/></D:prop>
  <C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VEVENT">
    <C:time-range start="%s" end="%s"/>
  </C:comp-filter></C:comp-filter></C:filter>
</C:calendar-query>`, w.From.UTC().Format("20060102T150405Z"), w.To.UTC().Format("20060102T150405Z"))
	req, err := http.NewRequestWithContext(ctx, "REPORT", s.URL, strings.NewReader(query))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/xml; charset=utf-8")
	req.Header.Set("Depth", "1")
	req.SetBasicAuth(s.User, password)
	body, err := f.do(req)
	if err != nil {
		return nil, err
	}
	return ParseMultistatus(body)
}

// maxResponse caps a feed or REPORT body. A larger one fails the fetch
// rather than being parsed cut short.
var maxResponse int64 = 32 << 20

func (f HTTPFetcher) do(req *http.Request) ([]byte, error) {
	req.Header.Set("User-Agent", "subcult-calendar/1")
	resp, err := f.client().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponse+1))
	if err != nil {
		return nil, err
	}
	if int64(len(body)) > maxResponse {
		return nil, fmt.Errorf("%s: response larger than %d MiB", req.URL.Host, maxResponse>>20)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s: HTTP %d", req.URL.Host, resp.StatusCode)
	}
	return body, nil
}

// ParseMultistatus pulls every calendar-data text out of a CalDAV
// multistatus response.
func ParseMultistatus(body []byte) ([]string, error) {
	var ms struct {
		Responses []struct {
			Propstats []struct {
				Status string `xml:"status"`
				Prop   struct {
					CalendarData string `xml:"urn:ietf:params:xml:ns:caldav calendar-data"`
				} `xml:"prop"`
			} `xml:"propstat"`
		} `xml:"response"`
	}
	if err := xml.Unmarshal(bytes.TrimSpace(body), &ms); err != nil {
		return nil, fmt.Errorf("multistatus: %w", err)
	}
	var out []string
	for _, r := range ms.Responses {
		for _, p := range r.Propstats {
			if strings.TrimSpace(p.Prop.CalendarData) != "" {
				out = append(out, p.Prop.CalendarData)
			}
		}
	}
	return out, nil
}
