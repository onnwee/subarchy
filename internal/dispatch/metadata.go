// Package dispatch finds, describes and runs subcult commands.
//
// A command is an executable named subcult-<group>-<action>... on PATH.
// Scripts describe themselves with header comments:
//
//	# subcult:summary=Apply a theme
//	# subcult:args=<theme-id>
//	# subcult:examples=subcult theme set subcult-minimal | subcult theme list
//	# subcult:hidden=true
//	# subcult:requires-sudo=true
//	# subcult:dangerous=true
//	# subcult:silent=true
package dispatch

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strings"
)

// metadataPrefix marks a metadata comment line in a command script.
const metadataPrefix = "subcult:"

// maxHeaderLines bounds how far into a script metadata is read.
const maxHeaderLines = 40

// Metadata describes one command, as read from its script header.
type Metadata struct {
	Summary      string   `json:"summary"`
	Args         string   `json:"args"`
	Examples     []string `json:"examples"`
	Hidden       bool     `json:"hidden"`
	RequiresSudo bool     `json:"requires_sudo"`
	Dangerous    bool     `json:"dangerous"`
	// Silent marks a command with no output to read; the launcher runs it
	// without a terminal.
	Silent bool `json:"silent"`
}

// ReadMetadata parses the metadata header of the file at path. Binary files
// and files without a header yield empty metadata and no error.
func ReadMetadata(path string) (Metadata, error) {
	f, err := os.Open(path)
	if err != nil {
		return Metadata{}, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	return ParseMetadata(f)
}

// ParseMetadata reads metadata comment lines from the start of r.
func ParseMetadata(r io.Reader) (Metadata, error) {
	var m Metadata
	br := bufio.NewReader(r)
	head, err := br.Peek(512)
	if err != nil && err != io.EOF && err != bufio.ErrBufferFull {
		return m, fmt.Errorf("read header: %w", err)
	}
	if bytes.IndexByte(head, 0) >= 0 {
		return m, nil // binary
	}
	sc := bufio.NewScanner(br)
	for n := 0; sc.Scan() && n < maxHeaderLines; n++ {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, "#") {
			if line == "" {
				continue
			}
			break
		}
		body := strings.TrimSpace(strings.TrimPrefix(line, "#"))
		if !strings.HasPrefix(body, metadataPrefix) {
			continue
		}
		key, value, ok := strings.Cut(strings.TrimPrefix(body, metadataPrefix), "=")
		if !ok {
			continue
		}
		value = strings.TrimSpace(value)
		switch strings.TrimSpace(key) {
		case "summary":
			m.Summary = value
		case "args":
			m.Args = value
		case "examples":
			for _, ex := range strings.Split(value, "|") {
				if ex = strings.TrimSpace(ex); ex != "" {
					m.Examples = append(m.Examples, ex)
				}
			}
		case "hidden":
			m.Hidden = value == "true"
		case "requires-sudo":
			m.RequiresSudo = value == "true"
		case "dangerous":
			m.Dangerous = value == "true"
		case "silent":
			m.Silent = value == "true"
		}
	}
	if err := sc.Err(); err != nil {
		return m, fmt.Errorf("scan header: %w", err)
	}
	return m, nil
}
