package font

import (
	"encoding/xml"
	"fmt"
	"sort"
	"strings"
)

// UserConfName is the user's role file in ~/.config/fontconfig/conf.d/. It
// loads after the system roles (50-subarchy-roles.conf) and, like them,
// uses prepend_first, so it wins.
const UserConfName = "60-subcult-fonts.conf"

// RenderUserConf writes one prepend_first match per role.
func RenderUserConf(roles map[Role]string) string {
	keys := make([]string, 0, len(roles))
	for r := range roles {
		keys = append(keys, string(r))
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteString("<?xml version=\"1.0\"?>\n<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">\n")
	b.WriteString("<!-- Written by `subcult font set`; edit with that command. -->\n<fontconfig>\n")
	for _, k := range keys {
		var fam strings.Builder
		_ = xml.EscapeText(&fam, []byte(roles[Role(k)]))
		fmt.Fprintf(&b, "  <match target=\"pattern\">\n    <test qual=\"any\" name=\"family\"><string>%s</string></test>\n"+
			"    <edit name=\"family\" mode=\"prepend_first\" binding=\"strong\"><string>%s</string></edit>\n  </match>\n",
			k, fam.String())
	}
	b.WriteString("</fontconfig>\n")
	return b.String()
}

type confDoc struct {
	Matches []struct {
		Test struct {
			String string `xml:"string"`
		} `xml:"test"`
		Edit struct {
			Strings []string `xml:"string"`
		} `xml:"edit"`
	} `xml:"match"`
}

// ParseUserConf reads a file RenderUserConf wrote back into roles.
func ParseUserConf(data string) (map[Role]string, error) {
	var doc confDoc
	dec := xml.NewDecoder(strings.NewReader(data))
	dec.Strict = false
	if err := dec.Decode(&doc); err != nil {
		return nil, fmt.Errorf("font role file: %w", err)
	}
	roles := map[Role]string{}
	for _, m := range doc.Matches {
		r := Role(m.Test.String)
		if (r == Mono || r == UI || r == Serif) && len(m.Edit.Strings) > 0 {
			roles[r] = m.Edit.Strings[0]
		}
	}
	return roles, nil
}
