package apps

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Web apps (ADR 0042, app list): a site opened in a Chromium app window
// from its own desktop entry in the user's applications folder. Chromium
// names such a window chrome-<host>_<path>-Default with each slash of the
// path as an underscore (a bare host has the path "/"), which the entry's
// StartupWMClass repeats so the window finds its entry. Nothing is fetched
// at install time: the icon is the one given, else a generic one.

var notIDChars = regexp.MustCompile(`[^a-z0-9]+`)

// WebappID is the desktop entry's file name for a web app's name:
// "Google Maps" -> "google-maps".
func WebappID(name string) (string, error) {
	id := strings.Trim(notIDChars.ReplaceAllString(strings.ToLower(name), "-"), "-")
	if id == "" {
		return "", fmt.Errorf("web app name %q leaves nothing to name the entry", name)
	}
	return id, nil
}

// NormalizeURL adds https:// when the URL has no scheme and checks that it
// is an http or https address without whitespace.
func NormalizeURL(raw string) (string, error) {
	u := strings.TrimSpace(raw)
	if u == "" {
		return "", errors.New("a web app needs a URL")
	}
	if strings.ContainsAny(u, " \t\n") {
		return "", fmt.Errorf("web app URL %q contains whitespace", raw)
	}
	if !regexp.MustCompile(`^[A-Za-z][A-Za-z0-9+.-]*:`).MatchString(u) {
		u = "https://" + u
	}
	p, err := url.Parse(u)
	if err != nil || (p.Scheme != "http" && p.Scheme != "https") || p.Host == "" {
		return "", fmt.Errorf("web app URL %q is not an http or https address", raw)
	}
	return u, nil
}

// WMClass is the window class Chromium gives an --app window for the URL.
func WMClass(u string) string {
	p, err := url.Parse(u)
	if err != nil {
		return ""
	}
	path := p.Path
	if path == "" {
		path = "/" // Chromium reads https://host as https://host/
	}
	path = strings.ReplaceAll(path, "/", "_")
	return "chrome-" + p.Host + "_" + path + "-Default"
}

// WebappDesktop renders the desktop entry.
func WebappDesktop(name, u, icon string) string {
	if icon == "" {
		icon = "web-browser"
	}
	return fmt.Sprintf("[Desktop Entry]\nVersion=1.0\nType=Application\nName=%s\nComment=%s\nExec=chromium %s\nIcon=%s\nStartupWMClass=%s\nStartupNotify=true\nTerminal=false\nCategories=Network;\n",
		desktopEscape(name), desktopEscape(u), desktopExecArg("--app="+u), icon, WMClass(u))
}

// Desktop Exec uses its own quoting rules, then expands field codes. The
// generic desktop string parser consumes one layer of backslash escapes first.
func desktopExecArg(s string) string {
	s = strings.ReplaceAll(s, "%", "%%")
	if !strings.ContainsAny(s, " \t\n\"'\\><~|&;$*?#()`") {
		return s
	}
	s = strings.NewReplacer(`\`, `\\\\`, `"`, `\\"`, "`", "\\\\`", "$", `\\$`).Replace(s)
	return `"` + s + `"`
}

func desktopEscape(s string) string {
	return strings.NewReplacer("\n", " ", "\r", " ").Replace(s)
}

// ErrIconFormat is WebappPlan's refusal of an icon the icon theme cannot
// find.
var ErrIconFormat = errors.New("icon must be PNG, SVG or XPM")

// WebappPlan returns the steps that install a web app: the icon copied
// into the user's icon theme when one is given, and the desktop entry.
func WebappPlan(appsDir, iconsDir, name, rawURL, iconFile string) ([]Step, error) {
	id, err := WebappID(name)
	if err != nil {
		return nil, err
	}
	u, err := NormalizeURL(rawURL)
	if err != nil {
		return nil, err
	}
	var steps []Step
	icon := ""
	if iconFile != "" {
		// The icon theme lookup finds only these formats in hicolor.
		ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(iconFile), "."))
		switch ext {
		case "":
			ext = "png"
		case "png", "svg", "xpm":
		default:
			return nil, ErrIconFormat
		}
		dest := filepath.Join(iconsDir, "hicolor", "256x256", "apps", id+"."+ext)
		steps = append(steps, Step{Argv: []string{"install", "-Dm644", iconFile, dest}})
		icon = id
	}
	steps = append(steps, Step{Path: filepath.Join(appsDir, id+".desktop"), Content: WebappDesktop(name, u, icon)})
	return steps, nil
}

// WebappRemovePlan returns the steps that remove a web app the user
// installed.
func WebappRemovePlan(appsDir, iconsDir, name string) ([]Step, error) {
	id, err := WebappID(name)
	if err != nil {
		return nil, err
	}
	argv := []string{"rm", "-f", filepath.Join(appsDir, id+".desktop")}
	dir := filepath.Join(iconsDir, "hicolor", "256x256", "apps")
	entries, err := os.ReadDir(dir)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasPrefix(entry.Name(), id+".") {
			argv = append(argv, filepath.Join(dir, entry.Name()))
		}
	}
	return []Step{{Argv: argv}}, nil
}
