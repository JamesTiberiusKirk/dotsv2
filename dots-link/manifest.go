package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Manifest is a host file as a list of raw lines, so comments and blanks survive
// rewrites. Entries() yields the meaningful (non-comment, non-blank) lines.
type Manifest struct {
	Path  string
	Lines []string
}

// ParseManifest reads a host manifest. A missing file is reported via the
// returned ok=false, not an error, so callers can decide what that means.
func ParseManifest(path string) (m *Manifest, ok bool, err error) {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, fmt.Errorf("read manifest %s: %w", path, err)
	}
	return parseManifestBytes(path, data), true, nil
}

func parseManifestBytes(path string, data []byte) *Manifest {
	text := strings.ReplaceAll(string(data), "\r\n", "\n")
	lines := strings.Split(text, "\n")
	// Split leaves a trailing "" for a final newline; drop it so we don't grow
	// the file by one blank line on every rewrite.
	if n := len(lines); n > 0 && lines[n-1] == "" {
		lines = lines[:n-1]
	}
	return &Manifest{Path: path, Lines: lines}
}

func isEntryLine(line string) bool {
	t := strings.TrimSpace(line)
	return t != "" && !strings.HasPrefix(t, "#")
}

// Entries returns the trimmed entry paths in file order.
func (m *Manifest) Entries() []string {
	var out []string
	for _, l := range m.Lines {
		if isEntryLine(l) {
			out = append(out, strings.TrimSpace(l))
		}
	}
	return out
}

// Has reports whether entry is present (exact match against a trimmed line).
func (m *Manifest) Has(entry string) bool {
	for _, l := range m.Lines {
		if isEntryLine(l) && strings.TrimSpace(l) == entry {
			return true
		}
	}
	return false
}

// RemoveEntry drops every line matching entry. Returns how many were removed.
func (m *Manifest) RemoveEntry(entry string) int {
	kept := m.Lines[:0:0]
	removed := 0
	for _, l := range m.Lines {
		if isEntryLine(l) && strings.TrimSpace(l) == entry {
			removed++
			continue
		}
		kept = append(kept, l)
	}
	m.Lines = kept
	return removed
}

// Bytes serializes the manifest back to file content with a trailing newline.
func (m *Manifest) Bytes() []byte {
	return []byte(strings.Join(m.Lines, "\n") + "\n")
}

// Write persists the manifest atomically (temp file + rename).
func (m *Manifest) Write() error {
	return writeFileAtomic(m.Path, m.Bytes(), 0o644)
}

// listHostManifests returns the paths of every file in hosts/.
func listHostManifests(env *Env) ([]string, error) {
	ents, err := os.ReadDir(env.HostsDir)
	if err != nil {
		return nil, fmt.Errorf("read hosts dir: %w", err)
	}
	var out []string
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		out = append(out, filepath.Join(env.HostsDir, e.Name()))
	}
	return out, nil
}

func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(perm); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}
