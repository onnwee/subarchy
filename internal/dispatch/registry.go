package dispatch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// MetadataFlag asks a compiled command to describe its subcommands as JSON.
const MetadataFlag = "--subcult-metadata"

// probeTimeout bounds how long a compiled command may take to describe itself.
const probeTimeout = 2 * time.Second

// Described is one subcommand as reported by a compiled command.
type Described struct {
	Words []string `json:"words"`
	Metadata
}

// Prefix is the executable name prefix every subcult command carries.
const Prefix = "subcult-"

// Command is one discovered subcult command.
type Command struct {
	// Words are the route after "subcult", e.g. ["theme", "set"].
	Words []string `json:"-"`
	// Route is the full invocation, e.g. "subcult theme set".
	Route string `json:"route"`
	// Group is the first route word.
	Group string `json:"group"`
	// Binary is the executable name, e.g. "subcult-theme-set".
	Binary string `json:"binary"`
	// Path is the resolved executable path.
	Path string `json:"path"`
	// ArgPrefix is prepended to the user's arguments when one compiled
	// binary serves several routes, e.g. ["list"] for "subcult app list"
	// served by subcult-app.
	ArgPrefix []string `json:"-"`
	Metadata
}

// Registry holds the commands found on a search path, keyed by binary name.
type Registry struct {
	byBinary map[string]Command
}

// Discover scans the directories in dirs (earlier wins, as with PATH) for
// executables named subcult-*.
func Discover(dirs []string) (*Registry, error) {
	reg := &Registry{byBinary: map[string]Command{}}
	for _, dir := range dirs {
		if dir == "" {
			continue
		}
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue // missing PATH entries are normal
		}
		for _, e := range entries {
			name := e.Name()
			if !strings.HasPrefix(name, Prefix) || len(name) == len(Prefix) {
				continue
			}
			if _, seen := reg.byBinary[name]; seen {
				continue
			}
			path := filepath.Join(dir, name)
			info, err := os.Stat(path) // follows symlinks
			if err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
				continue
			}
			words := strings.Split(strings.TrimPrefix(name, Prefix), "-")
			bin, err := isBinary(path)
			if err != nil {
				return nil, err
			}
			if bin {
				if described := probe(path, words); len(described) > 0 {
					for _, d := range described {
						key := Prefix + strings.Join(d.Words, "-")
						if _, seen := reg.byBinary[key]; seen {
							continue
						}
						reg.byBinary[key] = Command{
							Words:     d.Words,
							Route:     "subcult " + strings.Join(d.Words, " "),
							Group:     d.Words[0],
							Binary:    name,
							Path:      path,
							ArgPrefix: d.Words[len(words):],
							Metadata:  d.Metadata,
						}
					}
					continue
				}
			}
			meta, err := ReadMetadata(path)
			if err != nil {
				return nil, fmt.Errorf("metadata for %s: %w", name, err)
			}
			reg.byBinary[name] = Command{
				Words:    words,
				Route:    "subcult " + strings.Join(words, " "),
				Group:    words[0],
				Binary:   name,
				Path:     path,
				Metadata: meta,
			}
		}
	}
	return reg, nil
}

// Commands returns all commands sorted by route; hidden ones only if all.
func (r *Registry) Commands(all bool) []Command {
	out := make([]Command, 0, len(r.byBinary))
	for _, c := range r.byBinary {
		if c.Hidden && !all {
			continue
		}
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Route < out[j].Route })
	return out
}

// Group returns the visible commands whose route starts with words.
func (r *Registry) Group(words []string, all bool) []Command {
	var out []Command
	for _, c := range r.Commands(all) {
		if len(c.Words) <= len(words) {
			continue
		}
		match := true
		for i, w := range words {
			if c.Words[i] != w {
				match = false
				break
			}
		}
		if match {
			out = append(out, c)
		}
	}
	return out
}

// Resolve finds the command for args using the longest matching prefix of
// words, the way "subcult theme set foo" resolves to subcult-theme-set with
// the argument "foo". It returns the command and the remaining arguments.
func (r *Registry) Resolve(args []string) (Command, []string, bool) {
	for n := len(args); n > 0; n-- {
		if strings.HasPrefix(args[n-1], "-") {
			continue
		}
		name := Prefix + strings.Join(args[:n], "-")
		if c, ok := r.byBinary[name]; ok {
			return c, args[n:], true
		}
	}
	return Command{}, nil, false
}

// Suggest returns up to max routes close to the unknown words.
func (r *Registry) Suggest(words []string, max int) []string {
	want := strings.Join(words, " ")
	type scored struct {
		route string
		dist  int
	}
	var cands []scored
	for _, c := range r.Commands(false) {
		route := strings.TrimPrefix(c.Route, "subcult ")
		d := levenshtein(want, route)
		if strings.HasPrefix(route, want) {
			d = 0
		}
		if d <= 3 || strings.HasPrefix(route, words[0]+" ") {
			cands = append(cands, scored{c.Route, d})
		}
	}
	sort.Slice(cands, func(i, j int) bool {
		if cands[i].dist != cands[j].dist {
			return cands[i].dist < cands[j].dist
		}
		return cands[i].route < cands[j].route
	})
	var out []string
	for i := 0; i < len(cands) && i < max; i++ {
		out = append(out, cands[i].route)
	}
	return out
}

func levenshtein(a, b string) int {
	prev := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		cur := make([]int, len(b)+1)
		cur[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			cur[j] = min(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
		}
		prev = cur
	}
	return prev[len(b)]
}

// isBinary reports whether the file at path is not a text script.
func isBinary(path string) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return false, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	head := make([]byte, 512)
	n, err := f.Read(head)
	if err != nil && n == 0 {
		return false, nil
	}
	return bytes.IndexByte(head[:n], 0) >= 0, nil
}

// probe runs a compiled command with MetadataFlag and returns the
// subcommands it reports. Only routes under the binary's own words are kept,
// so subcult-app cannot claim "subcult theme set". Failures yield nothing;
// the binary is then listed as a single command without metadata.
func probe(path string, words []string) []Described {
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, MetadataFlag).Output()
	if err != nil {
		return nil
	}
	var described []Described
	if err := json.Unmarshal(out, &described); err != nil {
		return nil
	}
	var kept []Described
	for _, d := range described {
		if len(d.Words) < len(words) {
			continue
		}
		ok := true
		for i, w := range words {
			if d.Words[i] != w {
				ok = false
				break
			}
		}
		if ok {
			kept = append(kept, d)
		}
	}
	return kept
}
