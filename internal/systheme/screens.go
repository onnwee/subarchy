package systheme

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"image/png"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Screens names the art set each system screen shows (ADR 0052): the boot
// splash and boot menu, the login screen and the lock screen. An art set is
// a folder of images under ScreensSystemDir (shipped) or ScreensLocalDir
// (added on this machine with `subcult theme screens add`):
//
//	boot.png    the boot splash's logo
//	login.png   the login screen's logo
//	lock.png    the lock screen's logo
//	title.txt   one line: the boot menu's branding and the logos' alt text
//
// A set may leave any of them out; that screen then keeps its packaged art.
// The choice is the user's ~/.config/subcult/theme/screens.json, beside the
// palette, so a theme can carry it.
type Screens struct {
	Boot  string `json:"boot,omitempty"`
	Login string `json:"login,omitempty"`
	Lock  string `json:"lock,omitempty"`
}

// DefaultScreens is the choice when the user has made none: Subarchy's
// wordmark at boot, the SUBCULT lockup on the screens after it.
var DefaultScreens = Screens{Boot: "subarchy", Login: "subcult", Lock: "subcult"}

// Art set folders under the root, local first.
const (
	ScreensLocalDir  = "etc/subcult/screens"
	ScreensSystemDir = "usr/share/subcult/screens"
)

// ScreenFiles are the files an art set may hold.
var ScreenFiles = []string{"boot.png", "login.png", "lock.png", "title.txt"}

// MaxScreenImage bounds an art set's image, in bytes and in pixels a side.
const (
	MaxScreenImage = 8 << 20
	MaxScreenSide  = 8192
)

var setName = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,31}$`)
var titleText = regexp.MustCompile(`^[A-Za-z0-9 ./_&:'-]{1,48}$`)

// ValidSetName reports whether name can name an art set.
func ValidSetName(name string) bool { return setName.MatchString(name) }

// WithDefaults fills the screens the user left unset.
func (s Screens) WithDefaults() Screens {
	if s.Boot == "" {
		s.Boot = DefaultScreens.Boot
	}
	if s.Login == "" {
		s.Login = DefaultScreens.Login
	}
	if s.Lock == "" {
		s.Lock = DefaultScreens.Lock
	}
	return s
}

func (s Screens) check() error {
	for _, n := range []string{s.Boot, s.Login, s.Lock} {
		if n != "" && !ValidSetName(n) {
			return fmt.Errorf("%q is not an art set name (a-z, 0-9 and -, up to 32)", n)
		}
	}
	return nil
}

// ParseScreens reads screens.json. Unknown keys are refused, so a typo
// does not silently fall back to the default.
func ParseScreens(data []byte) (Screens, error) {
	var s Screens
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&s); err != nil {
		return Screens{}, fmt.Errorf("screens: %w", err)
	}
	if err := s.check(); err != nil {
		return Screens{}, fmt.Errorf("screens: %w", err)
	}
	return s, nil
}

// Args renders the choice for the privileged run: "boot=…,login=…".
// The lock screen runs as the user and reads screens.json itself.
func (s Screens) Args() string {
	s = s.WithDefaults()
	return "boot=" + s.Boot + ",login=" + s.Login
}

// ParseScreensArgs is the inverse of Args, as strict as ParseScreens.
func ParseScreensArgs(arg string) (Screens, error) {
	var s Screens
	if arg == "" {
		return s.WithDefaults(), nil
	}
	for _, part := range strings.Split(arg, ",") {
		k, v, ok := strings.Cut(part, "=")
		if !ok || !ValidSetName(v) {
			return Screens{}, fmt.Errorf("%q is not screen=set", part)
		}
		switch k {
		case "boot":
			s.Boot = v
		case "login":
			s.Login = v
		default:
			return Screens{}, fmt.Errorf("%q: the screens here are boot and login", part)
		}
	}
	return s.WithDefaults(), nil
}

// CheckScreenImage accepts a PNG within the size limits.
func CheckScreenImage(data []byte) error {
	if len(data) > MaxScreenImage {
		return fmt.Errorf("larger than %d MiB", MaxScreenImage>>20)
	}
	cfg, err := png.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("not a PNG: %w", err)
	}
	if cfg.Width < 1 || cfg.Height < 1 || cfg.Width > MaxScreenSide || cfg.Height > MaxScreenSide {
		return fmt.Errorf("%dx%d pixels; up to %d a side", cfg.Width, cfg.Height, MaxScreenSide)
	}
	return nil
}

// CheckScreenTitle accepts title.txt's one line and returns it trimmed.
func CheckScreenTitle(data []byte) (string, error) {
	t := strings.TrimSpace(string(data))
	if strings.ContainsAny(t, "\r\n") || !titleText.MatchString(t) {
		return "", errors.New("title.txt is one line of up to 48 letters, digits, spaces and . / _ & : ' -")
	}
	return t, nil
}

// ScreenFile finds file in the named set, local folder first, and returns
// its contents and absolute path. ok is false when no folder has it. A
// file that is there but is not a regular file, or fails its check, is an
// error: root reads these, so a link or a huge file is refused.
func ScreenFile(root, set, file string) (data []byte, path string, ok bool, err error) {
	if !ValidSetName(set) {
		return nil, "", false, fmt.Errorf("%q is not an art set name", set)
	}
	for _, dir := range []string{ScreensLocalDir, ScreensSystemDir} {
		rel := filepath.Join(dir, set, file)
		full := filepath.Join(root, rel)
		fi, err := os.Lstat(full)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, "", false, err
		}
		if !fi.Mode().IsRegular() {
			return nil, "", false, fmt.Errorf("/%s is not a regular file", rel)
		}
		if fi.Size() > MaxScreenImage {
			return nil, "", false, fmt.Errorf("/%s is larger than %d MiB", rel, MaxScreenImage>>20)
		}
		data, err := os.ReadFile(full)
		if err != nil {
			return nil, "", false, err
		}
		if strings.HasSuffix(file, ".png") {
			err = CheckScreenImage(data)
		} else {
			_, err = CheckScreenTitle(data)
		}
		if err != nil {
			return nil, "", false, fmt.Errorf("/%s: %w", rel, err)
		}
		return data, "/" + rel, true, nil
	}
	return nil, "", false, nil
}

// screenTitle is the set's title, or "" when it has none.
func screenTitle(root, set string) (string, error) {
	data, _, ok, err := ScreenFile(root, set, "title.txt")
	if err != nil || !ok {
		return "", err
	}
	return CheckScreenTitle(data)
}

// ScreenSets lists the art set names under root, local and shipped, sorted.
func ScreenSets(root string) []string {
	seen := map[string]bool{}
	for _, dir := range []string{ScreensLocalDir, ScreensSystemDir} {
		entries, _ := os.ReadDir(filepath.Join(root, dir))
		for _, e := range entries {
			if e.IsDir() && ValidSetName(e.Name()) {
				seen[e.Name()] = true
			}
		}
	}
	names := make([]string, 0, len(seen))
	for n := range seen {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}
