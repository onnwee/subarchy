package font

import (
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"sort"
	"strings"
)

// UserConfPath is the user's role file, relative to $HOME. The system roles
// file (44-subarchy-roles.conf) includes subcult/fonts.conf from
// XDG_CONFIG_HOME ahead of its own rules, so the user's families win.
const UserConfPath = ".config/subcult/fonts.conf"

// followsMarker precedes a match written because a role follows monospace
// (the interface role by default) rather than being set on its own.
const followsMarker = " subcult: follows monospace "

// UserConf is the user's role choices. Follows marks roles that were
// derived from the monospace choice and change with it.
type UserConf struct {
	Roles   map[Role]string
	Follows map[Role]bool
}

// RenderUserConf writes one match per role that inserts the family just
// before the generic name (mode prepend), like the system roles.
func RenderUserConf(c UserConf) string {
	keys := make([]string, 0, len(c.Roles))
	for r := range c.Roles {
		keys = append(keys, string(r))
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteString("<?xml version=\"1.0\"?>\n<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">\n")
	b.WriteString("<!-- Written by `subcult font set`; change it with that command. -->\n<fontconfig>\n")
	for _, k := range keys {
		var fam strings.Builder
		_ = xml.EscapeText(&fam, []byte(c.Roles[Role(k)]))
		if c.Follows[Role(k)] {
			b.WriteString("  <!--" + followsMarker + "-->\n")
		}
		fmt.Fprintf(&b, "  <match target=\"pattern\">\n    <test qual=\"any\" name=\"family\"><string>%s</string></test>\n"+
			"    <edit name=\"family\" mode=\"prepend\" binding=\"strong\"><string>%s</string></edit>\n  </match>\n",
			k, fam.String())
	}
	b.WriteString("</fontconfig>\n")
	return b.String()
}

type match struct {
	Test struct {
		String string `xml:"string"`
	} `xml:"test"`
	Edit struct {
		Strings []string `xml:"string"`
	} `xml:"edit"`
}

// ParseUserConf reads a file RenderUserConf wrote.
func ParseUserConf(data string) (UserConf, error) {
	c := UserConf{Roles: map[Role]string{}, Follows: map[Role]bool{}}
	dec := xml.NewDecoder(strings.NewReader(data))
	follows := false
	sawRoot := false
	for {
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return UserConf{}, fmt.Errorf("font role file: %w", err)
		}
		switch t := tok.(type) {
		case xml.Comment:
			follows = string(t) == followsMarker
		case xml.StartElement:
			if t.Name.Local == "fontconfig" {
				sawRoot = true
				continue
			}
			if t.Name.Local != "match" {
				continue
			}
			var m match
			if err := dec.DecodeElement(&m, &t); err != nil {
				return UserConf{}, fmt.Errorf("font role file: %w", err)
			}
			r := Role(m.Test.String)
			if (r == Mono || r == UI || r == Serif) && len(m.Edit.Strings) > 0 {
				c.Roles[r] = m.Edit.Strings[0]
				if follows {
					c.Follows[r] = true
				}
			}
			follows = false
		}
	}
	if !sawRoot {
		return UserConf{}, errors.New("font role file: no <fontconfig> element")
	}
	return c, nil
}
