package font

import (
	"fmt"
	"strconv"
	"strings"
)

// Verdict is what `subcult font check` says about a face.
type Verdict int

// Verdicts, best first.
const (
	FullNerd Verdict = iota
	FallbackIcons
	InterfaceOnly
	BreaksTUI
)

func (v Verdict) String() string {
	switch v {
	case FullNerd:
		return "full Nerd Font"
	case FallbackIcons:
		return "works, icons from the Symbols fallback"
	case InterfaceOnly:
		return "interface text only (not monospace)"
	case BreaksTUI:
		return "breaks terminal UIs (no box drawing)"
	}
	return fmt.Sprintf("Verdict(%d)", int(v))
}

// Range is an inclusive span of code points.
type Range struct{ Lo, Hi rune }

// FontInfo is what the check needs from one face.
type FontInfo struct {
	Family  string
	Spacing int // fontconfig: 100 mono, 90 dual, 0 proportional
	Charset []Range
}

// Has reports whether the face covers r.
func (f FontInfo) Has(r rune) bool {
	for _, x := range f.Charset {
		if r >= x.Lo && r <= x.Hi {
			return true
		}
	}
	return false
}

// FcQueryFormat is the fc-query/fc-list format ParseFcQuery reads.
const FcQueryFormat = "%{family[0]}\t%{spacing}\t%{charset}\n"

// ParseFcQuery reads one face per line in FcQueryFormat. An empty spacing
// means proportional.
func ParseFcQuery(out string) ([]FontInfo, error) {
	var infos []FontInfo
	for n, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		if line == "" {
			continue
		}
		f := strings.Split(line, "\t")
		if len(f) != 3 {
			return nil, fmt.Errorf("fc-query line %d: want family, spacing and charset", n+1)
		}
		fi := FontInfo{Family: f[0]}
		if f[1] != "" {
			s, err := strconv.Atoi(f[1])
			if err != nil {
				return nil, fmt.Errorf("fc-query line %d: spacing %q", n+1, f[1])
			}
			fi.Spacing = s
		}
		for _, tok := range strings.Fields(f[2]) {
			lo, hi, isRange := strings.Cut(tok, "-")
			if !isRange {
				hi = lo
			}
			a, err1 := strconv.ParseUint(lo, 16, 32)
			b, err2 := strconv.ParseUint(hi, 16, 32)
			if err1 != nil || err2 != nil || b < a {
				return nil, fmt.Errorf("fc-query line %d: charset %q", n+1, tok)
			}
			fi.Charset = append(fi.Charset, Range{rune(a), rune(b)})
		}
		infos = append(infos, fi)
	}
	return infos, nil
}

// Check grades a face: proportional faces are for interface text, a
// monospace face without the box-drawing block breaks terminal UIs, and
// one with Powerline (U+E0B0) and Nerd (U+F015) glyphs needs no fallback.
func Check(fi FontInfo) Verdict {
	if fi.Spacing < 90 {
		return InterfaceOnly
	}
	for r := rune(0x2500); r <= 0x257F; r++ {
		if !fi.Has(r) {
			return BreaksTUI
		}
	}
	if fi.Has(0xE0B0) && fi.Has(0xF015) {
		return FullNerd
	}
	return FallbackIcons
}
