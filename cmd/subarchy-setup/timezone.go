package main

// The time zone guess (issue #124): the time zone list opens on the zone
// of the network's location when the live system is online, as
// Omarchy's installer does, else on the usual zone for the language
// chosen, else on UTC. Either way it is only the first row: the user
// confirms it or types another.

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/setup"
)

// zoneServices are geo-IP lookups that answer with the time zone of the
// address a request comes from. Both are among the services tzupdate
// asks (ADR 0024). A lookup sends them the network's public address,
// and nothing else.
var zoneServices = []struct {
	url  string
	keys []string // where the zone is in the JSON reply
}{
	{"https://ipapi.co/json/", []string{"timezone"}},
	{"https://ipwho.is/", []string{"timezone", "id"}},
}

// zoneLookupTime is how long the time zone screen waits for an answer.
const zoneLookupTime = 4 * time.Second

// lookupZone asks every service at once and returns the first zone one
// names, or "" when none has within zoneLookupTime.
func lookupZone(get func(ctx context.Context, url string) ([]byte, error)) string {
	ctx, cancel := context.WithTimeout(context.Background(), zoneLookupTime)
	defer cancel()
	found := make(chan string, len(zoneServices))
	for _, svc := range zoneServices {
		go func() {
			zone := ""
			if body, err := get(ctx, svc.url); err == nil {
				zone = zoneIn(body, svc.keys)
			}
			found <- zone
		}()
	}
	for range zoneServices {
		select {
		case zone := <-found:
			if zone != "" {
				return zone
			}
		case <-ctx.Done():
			return ""
		}
	}
	return ""
}

// zoneIn returns the string at keys in a JSON object, or "".
func zoneIn(body []byte, keys []string) string {
	var v any
	if json.Unmarshal(body, &v) != nil {
		return ""
	}
	for _, k := range keys {
		m, ok := v.(map[string]any)
		if !ok {
			return ""
		}
		v = m[k]
	}
	s, _ := v.(string)
	return s
}

// httpGet fetches a URL, up to 64 KiB of it.
func httpGet(ctx context.Context, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "subarchy-setup")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s", url, resp.Status)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 64<<10))
}

// languageZones is the zone of the country a language goes with, for
// when the network cannot say: its capital's, as in Omarchy's language
// defaults. A language used across several countries or zones (English
// (US), French (Canada), Spanish (Latin America)) has none.
var languageZones = map[string]string{
	"en_GB.UTF-8": "Europe/London", "bg_BG.UTF-8": "Europe/Sofia", "ca_ES.UTF-8": "Europe/Madrid",
	"hr_HR.UTF-8": "Europe/Zagreb", "cs_CZ.UTF-8": "Europe/Prague", "da_DK.UTF-8": "Europe/Copenhagen",
	"nl_NL.UTF-8": "Europe/Amsterdam", "et_EE.UTF-8": "Europe/Tallinn", "fi_FI.UTF-8": "Europe/Helsinki",
	"fr_FR.UTF-8": "Europe/Paris", "de_DE.UTF-8": "Europe/Berlin", "de_CH.UTF-8": "Europe/Zurich",
	"el_GR.UTF-8": "Europe/Athens", "hu_HU.UTF-8": "Europe/Budapest", "is_IS.UTF-8": "Atlantic/Reykjavik",
	"it_IT.UTF-8": "Europe/Rome", "lv_LV.UTF-8": "Europe/Riga", "lt_LT.UTF-8": "Europe/Vilnius",
	"nb_NO.UTF-8": "Europe/Oslo", "pl_PL.UTF-8": "Europe/Warsaw", "pt_PT.UTF-8": "Europe/Lisbon",
	"pt_BR.UTF-8": "America/Sao_Paulo", "ro_RO.UTF-8": "Europe/Bucharest", "ru_RU.UTF-8": "Europe/Moscow",
	"sk_SK.UTF-8": "Europe/Bratislava", "sl_SI.UTF-8": "Europe/Ljubljana", "es_ES.UTF-8": "Europe/Madrid",
	"sv_SE.UTF-8": "Europe/Stockholm", "tr_TR.UTF-8": "Europe/Istanbul", "uk_UA.UTF-8": "Europe/Kyiv",
}

// zoneGuess is where the time zone screen's first row came from, kept
// across visits to the screen.
type zoneGuess struct {
	asked  bool   // the network was asked; it is asked once
	from   string // "network", "language", or "" for UTC
	picked bool   // the user chose a zone; no guess replaces it
}

// guess sets a.Timezone to the best guess, unless the user has chosen
// one, and returns the line that says where it came from. list is the
// zones on offer, sorted; a guess outside it is not used.
func (g *zoneGuess) guess(a *setup.Answers, lookup func() string, list []string, waiting func()) string {
	known := func(z string) bool { return listed(list, z) }
	if g.picked {
		return ""
	}
	if !g.asked && lookup != nil {
		g.asked = true
		waiting()
		if z := lookup(); known(z) {
			a.Timezone, g.from = z, "network"
		}
	}
	if g.from != "network" {
		// The language can have changed since the last visit.
		if z := languageZones[a.Locale]; known(z) {
			a.Timezone, g.from = z, "language"
		} else if g.from == "language" {
			a.Timezone, g.from = "UTC", ""
		}
	}
	switch g.from {
	case "network":
		return "Guessed from where your network is. Type to search for another."
	case "language":
		return "Guessed from the language you chose. Type to search for another."
	}
	return ""
}

// listed reports whether zone is in list, which is sorted.
func listed(list []string, zone string) bool {
	i := sort.SearchStrings(list, zone)
	return zone != "" && i < len(list) && list[i] == zone
}
