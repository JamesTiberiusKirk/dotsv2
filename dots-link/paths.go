package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// linkState describes the live $HOME path for an entry.
type linkState int

const (
	stateAbsent    linkState = iota // nothing there
	stateLinked                     // symlink into the repo, correct target
	stateWrongLink                  // symlink, but not pointing at our repo src
	stateDangling                   // symlink into the repo whose target is gone
	stateRealFile                   // a real file/dir occupies the path
)

// inspectDst classifies $HOME/<entry> using Lstat/Readlink (never Stat, so
// dangling links are still seen). target is the readlink result for symlinks.
func inspectDst(env *Env, entry string) (st linkState, target string, err error) {
	dst := env.dst(entry)
	fi, err := os.Lstat(dst)
	if os.IsNotExist(err) {
		return stateAbsent, "", nil
	}
	if err != nil {
		return stateAbsent, "", err
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		return stateRealFile, "", nil
	}
	target, err = os.Readlink(dst)
	if err != nil {
		return stateAbsent, "", err
	}
	abs := target
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(filepath.Dir(dst), abs)
	}
	want := env.src(entry)
	if filepath.Clean(abs) != filepath.Clean(want) {
		return stateWrongLink, target, nil
	}
	// Points at our src — is the src actually present?
	if _, e := os.Lstat(want); os.IsNotExist(e) {
		return stateDangling, target, nil
	}
	return stateLinked, target, nil
}

// pointsIntoRepo reports whether a symlink target resolves inside DotsDir.
func pointsIntoRepo(env *Env, dst, target string) bool {
	abs := target
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(filepath.Dir(dst), abs)
	}
	return isUnder(env.DotsDir, filepath.Clean(abs))
}

// isUnder reports whether path is base or sits beneath it.
func isUnder(base, path string) bool {
	base = filepath.Clean(base)
	path = filepath.Clean(path)
	if path == base {
		return true
	}
	rel, err := filepath.Rel(base, path)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// relUnder returns path relative to base if path is under base.
func relUnder(base, path string) (string, bool) {
	if !isUnder(base, path) {
		return "", false
	}
	rel, err := filepath.Rel(filepath.Clean(base), filepath.Clean(path))
	if err != nil {
		return "", false
	}
	return rel, true
}

// resolveEntry turns a user-supplied path into a manifest entry. It accepts the
// $HOME symlink, the repo file, or a path relative to cwd / $HOME / repo. A
// symlink is followed one hop so pointing at the live link resolves to the entry
// it manages. It does NOT consult the manifest — validation is the caller's job.
func resolveEntry(env *Env, input string) (string, error) {
	input = expandHome(env, input)
	for _, cand := range candidates(env, input) {
		if entry, ok := entryFromPath(env, cand); ok {
			return entry, nil
		}
	}
	return "", fmt.Errorf("%q is not under the repo (%s) or home (%s)", input, env.DotsDir, env.Home)
}

func expandHome(env *Env, p string) string {
	if p == "~" {
		return env.Home
	}
	if strings.HasPrefix(p, "~/") {
		return filepath.Join(env.Home, p[2:])
	}
	return p
}

// candidates yields absolute paths to try, in priority order.
func candidates(env *Env, input string) []string {
	if filepath.IsAbs(input) {
		return []string{filepath.Clean(input)}
	}
	var out []string
	if cwd, err := os.Getwd(); err == nil {
		out = append(out, filepath.Clean(filepath.Join(cwd, input)))
	}
	out = append(out,
		filepath.Clean(filepath.Join(env.Home, input)),
		filepath.Clean(filepath.Join(env.DotsDir, input)),
	)
	return out
}

// entryFromPath derives the manifest entry for one absolute candidate path.
func entryFromPath(env *Env, abs string) (string, bool) {
	// A symlink: follow one hop; if it lands in the repo, that's the entry.
	if fi, err := os.Lstat(abs); err == nil && fi.Mode()&os.ModeSymlink != 0 {
		if target, err := os.Readlink(abs); err == nil {
			t := target
			if !filepath.IsAbs(t) {
				t = filepath.Join(filepath.Dir(abs), t)
			}
			if rel, ok := relUnder(env.DotsDir, t); ok {
				return rel, true
			}
		}
	}
	// Directly inside the repo.
	if rel, ok := relUnder(env.DotsDir, abs); ok && rel != "." {
		return rel, true
	}
	// Under $HOME — the suffix is the entry.
	if rel, ok := relUnder(env.Home, abs); ok && rel != "." {
		return rel, true
	}
	return "", false
}
