package apps

import (
	"fmt"
	"path/filepath"
	"strings"
)

// Step is one action in a plan: run a command or write a file.
type Step struct {
	Argv    []string // command to run, when set
	Path    string   // file to write, when set
	Content string
}

// String describes the step for --dry-run output.
func (s Step) String() string {
	if s.Path != "" {
		return fmt.Sprintf("write %s: %s", s.Path, strings.TrimSpace(s.Content))
	}
	return strings.Join(s.Argv, " ")
}

// mimeTypes maps the roles the default picker hands to xdg-mime.
var mimeTypes = map[string][]string{
	"browser":      {"x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"},
	"mail":         {"x-scheme-handler/mailto"},
	"file-manager": {"inode/directory"},
	"editor":       {"text/plain", "text/markdown", "text/x-shellscript", "application/json", "application/toml", "application/x-yaml"},
	"pdf-viewer":   {"application/pdf"},
	"image-viewer": {"image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/bmp", "image/tiff"},
	"media-player": {
		"video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo",
		"audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/mp4",
	},
	"archive": {
		"application/zip", "application/x-tar", "application/x-compressed-tar", "application/x-xz-compressed-tar",
		"application/zstd", "application/x-7z-compressed", "application/vnd.rar",
	},
}

// MIMETypes returns the MIME types the default picker sets for role.
func MIMETypes(role string) []string { return mimeTypes[role] }

// InstallPlan returns the steps that install a. Web apps need the user's
// folders: see InstallPlanAt.
func InstallPlan(a App) ([]Step, error) {
	return InstallPlanAt(a, Paths{})
}

// InstallPlanAt returns the steps that install a, with web apps written
// into p.Applications.
func InstallPlanAt(a App, p Paths) ([]Step, error) {
	switch a.Source {
	case SourceWebapp:
		if p.Applications == "" {
			return nil, fmt.Errorf("%s: no applications folder to install a web app into", a.ID)
		}
		return WebappPlan(p.Applications, p.Icons, a.Name, a.URL, "")
	case SourceRepo, SourceAUR:
		// AUR apps are rebuilt into Subarchy's repository, so pacman serves both.
		return []Step{{Argv: append([]string{"sudo", "pacman", "-S", "--needed"}, a.Packages...)}}, nil
	case SourceMise:
		return []Step{{Argv: append([]string{"mise", "use", "--global"}, a.Packages...)}}, nil
	case SourceFlatpak:
		return []Step{{Argv: append([]string{"flatpak", "install", "--user", "flathub"}, a.Packages...)}}, nil
	default:
		return nil, fmt.Errorf("%s: installing %s apps is not supported yet", a.ID, a.Source)
	}
}

// RemovePlan returns the steps that remove a. Web apps: see RemovePlanAt.
func RemovePlan(a App) ([]Step, error) {
	return RemovePlanAt(a, Paths{})
}

// RemovePlanAt returns the steps that remove a, web apps from p.Applications.
func RemovePlanAt(a App, p Paths) ([]Step, error) {
	switch a.Source {
	case SourceWebapp:
		if p.Applications == "" {
			return nil, fmt.Errorf("%s: no applications folder to remove a web app from", a.ID)
		}
		return WebappRemovePlan(p.Applications, p.Icons, a.Name)
	case SourceRepo, SourceAUR:
		return []Step{{Argv: append([]string{"sudo", "pacman", "-Rns"}, a.Packages...)}}, nil
	case SourceMise:
		steps := make([]Step, len(a.Packages))
		for i, p := range a.Packages {
			steps[i] = Step{Argv: []string{"mise", "unuse", "--global", p}}
		}
		return steps, nil
	case SourceFlatpak:
		return []Step{{Argv: append([]string{"flatpak", "uninstall", "--user"}, a.Packages...)}}, nil
	default:
		return nil, fmt.Errorf("%s: removing %s apps is not supported yet", a.ID, a.Source)
	}
}

// DefaultPlan returns the steps that make a the system-wide handler for
// role in the user's session. Roles without a MIME or terminal mapping need
// no steps: Subarchy's launchers read the choice from the catalogue.
func DefaultPlan(role string, a App, configDir string) ([]Step, error) {
	if !a.HasRole(role) {
		return nil, fmt.Errorf("%s cannot be the %s", a.ID, role)
	}
	if role == "terminal" {
		if a.Desktop == "" {
			return nil, fmt.Errorf("%s: no desktop file to set as terminal", a.ID)
		}
		// xdg-terminal-exec reads the first entry of this list.
		return []Step{{Path: filepath.Join(configDir, "xdg-terminals.list"), Content: a.Desktop + "\n"}}, nil
	}
	types, ok := mimeTypes[role]
	if !ok {
		return nil, nil
	}
	if a.Desktop == "" {
		return nil, fmt.Errorf("%s: no desktop file to set as %s", a.ID, role)
	}
	steps := []Step{{Argv: append([]string{"xdg-mime", "default", a.Desktop}, types...)}}
	if role == "browser" {
		steps = append(steps, Step{Argv: []string{"xdg-settings", "set", "default-web-browser", a.Desktop}})
	}
	return steps, nil
}
