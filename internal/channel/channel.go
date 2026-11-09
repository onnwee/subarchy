// Package channel manages the update channels (ADR 0026): stable, where
// Arch packages come from the Arch Linux Archive at the snapshot date the
// subarchy package ships, and edge, where they come from the mirrors
// directly. The channel is two files under /etc/pacman.d that pacman.conf
// includes: subcult-mirrorlist for core, extra and multilib, and
// subcult-repo for the Subarchy repository's server.
package channel

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	Stable = "stable"
	Edge   = "edge"

	// SnapshotPath is the shipped snapshot date, YYYY/MM/DD, relative to root.
	SnapshotPath = "usr/share/subcult/default/pacman/snapshot"
	// MirrorlistPath and RepoPath are what pacman.conf includes, relative to root.
	MirrorlistPath = "etc/pacman.d/subcult-mirrorlist"
	RepoPath       = "etc/pacman.d/subcult-repo"
	PacmanConf     = "etc/pacman.conf"

	archive  = "https://archive.archlinux.org/repos/%s/$repo/os/$arch"
	registry = "https://git.subcult.tv/api/packages/subculture-collective/arch/%s/$arch"
)

var (
	snapshotRe = regexp.MustCompile(`^\d{4}/\d{2}/\d{2}$`)
	headerRe   = regexp.MustCompile(`(?m)^# subcult channel: (stable|edge)(?: \(snapshot (\d{4}/\d{2}/\d{2})\))?$`)
	includeRe  = regexp.MustCompile(`(?m)^(\s*Include\s*=\s*)/etc/pacman\.d/mirrorlist\s*$`)
)

// Valid reports whether name is a channel.
func Valid(name string) bool { return name == Stable || name == Edge }

// Snapshot reads the shipped snapshot date under root.
func Snapshot(root string) (string, error) {
	b, err := os.ReadFile(filepath.Join(root, SnapshotPath))
	if err != nil {
		return "", fmt.Errorf("snapshot date: %w", err)
	}
	s := strings.TrimSpace(string(b))
	if !snapshotRe.MatchString(s) {
		return "", fmt.Errorf("snapshot date %q is not YYYY/MM/DD", s)
	}
	return s, nil
}

// Mirrorlist is the content of subcult-mirrorlist for a channel.
func Mirrorlist(name, snapshot string) string {
	var b strings.Builder
	if name == Stable {
		fmt.Fprintf(&b, "# subcult channel: stable (snapshot %s)\n", snapshot)
		b.WriteString("# Arch packages from the Arch Linux Archive at Subarchy's tested snapshot\n")
		b.WriteString("# (ADR 0026). Written by `subcult channel set`; `subcult update` moves the\n")
		b.WriteString("# date when the subarchy package ships a new one.\n")
		fmt.Fprintf(&b, "Server = "+archive+"\n", snapshot)
	} else {
		b.WriteString("# subcult channel: edge\n")
		b.WriteString("# Arch packages from the mirrors directly (ADR 0026). Written by\n")
		b.WriteString("# `subcult channel set`.\n")
		b.WriteString("Include = /etc/pacman.d/mirrorlist\n")
	}
	return b.String()
}

// Repo is the content of subcult-repo for a channel: the Subarchy
// repository's server on git.subcult.tv (ADR 0025).
func Repo(name string) string {
	return fmt.Sprintf("# subcult channel: %s\n# Subarchy's own packages for this channel (ADR 0025).\nServer = "+registry+"\n", name, name)
}

// State is what the installed files say.
type State struct {
	Channel  string // "" when the files are not there
	Snapshot string // the stable mirrorlist's date
}

func (s State) String() string {
	switch {
	case s.Channel == "":
		return "unset (the mirrors directly; run `subcult channel set stable`)"
	case s.Channel == Stable:
		return fmt.Sprintf("stable (snapshot %s)", s.Snapshot)
	default:
		return "edge (the Arch mirrors directly)"
	}
}

// Current reads the channel from subcult-mirrorlist under root.
func Current(root string) (State, error) {
	b, err := os.ReadFile(filepath.Join(root, MirrorlistPath))
	if errors.Is(err, os.ErrNotExist) {
		return State{}, nil
	}
	if err != nil {
		return State{}, err
	}
	m := headerRe.FindStringSubmatch(string(b))
	if m == nil {
		return State{}, fmt.Errorf("%s has no channel header", MirrorlistPath)
	}
	return State{Channel: m[1], Snapshot: m[2]}, nil
}

// Set writes the channel's files and points pacman.conf's repository
// includes at subcult-mirrorlist. It returns the warning to show, if any.
func Set(root, name string) (warning string, err error) {
	if !Valid(name) {
		return "", fmt.Errorf("unknown channel %q (stable or edge)", name)
	}
	// The state before only decides the warning: a mirrorlist without the
	// header (edited by hand, or broken) is repaired, not refused.
	before, err := Current(root)
	if err != nil {
		before = State{}
	}
	snapshot := ""
	if name == Stable {
		if snapshot, err = Snapshot(root); err != nil {
			return "", err
		}
	}
	if err := write(filepath.Join(root, MirrorlistPath), Mirrorlist(name, snapshot)); err != nil {
		return "", err
	}
	if err := write(filepath.Join(root, RepoPath), Repo(name)); err != nil {
		return "", err
	}
	if err := pointIncludes(filepath.Join(root, PacmanConf)); err != nil {
		return "", err
	}
	if before.Channel == Edge && name == Stable {
		warning = "Packages installed from edge may be newer than the snapshot; pacman keeps them until the snapshot passes them."
	}
	return warning, nil
}

// Refresh rewrites the stable mirrorlist when the shipped snapshot date
// moved. It reports whether anything changed; edge and unset are left alone.
func Refresh(root string) (changed bool, err error) {
	cur, err := Current(root)
	if err != nil || cur.Channel != Stable {
		return false, err
	}
	snapshot, err := Snapshot(root)
	if err != nil {
		return false, err
	}
	if snapshot == cur.Snapshot {
		return false, nil
	}
	return true, write(filepath.Join(root, MirrorlistPath), Mirrorlist(Stable, snapshot))
}

// pointIncludes turns every `Include = /etc/pacman.d/mirrorlist` in
// pacman.conf into the channel's mirrorlist. A pacman.conf without one
// (already converted, or custom) is left as it is.
func pointIncludes(path string) error {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	out := includeRe.ReplaceAllString(string(b), "${1}/etc/pacman.d/subcult-mirrorlist")
	if out == string(b) {
		return nil
	}
	return write(path, out)
}

func write(path, content string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".subcult-tmp"
	if err := os.WriteFile(tmp, []byte(content), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
