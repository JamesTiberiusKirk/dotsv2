package main

import (
	"bytes"
	"errors"
	"os/exec"
	"strings"
)

type mergeStatus int

const (
	mergeNoUpstream  mergeStatus = iota // no @{u} configured / offline
	mergeUpToDate                       // nothing incoming
	mergeFastForward                    // HEAD is ancestor of upstream
	mergeClean                          // diverged, auto-mergeable
	mergeConflict                       // diverged, would conflict
	mergeDirty                          // local uncommitted changes block the merge
)

func (s mergeStatus) String() string {
	switch s {
	case mergeNoUpstream:
		return "no upstream"
	case mergeUpToDate:
		return "up to date"
	case mergeFastForward:
		return "fast-forward"
	case mergeClean:
		return "clean auto-merge"
	case mergeConflict:
		return "conflict"
	case mergeDirty:
		return "blocked by local changes"
	}
	return "?"
}

// git runs a git command in dir and returns trimmed stdout.
func git(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = err.Error()
		}
		return strings.TrimSpace(out.String()), errors.New(msg)
	}
	return strings.TrimSpace(out.String()), nil
}

// gitRaw is like git but only trims the trailing newline, preserving leading
// columns (needed for porcelain output where the status flags are positional).
func gitRaw(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = err.Error()
		}
		return "", errors.New(msg)
	}
	return strings.TrimRight(out.String(), "\n"), nil
}

// gitOK reports whether a git command exits zero (for predicate-style checks).
func gitOK(dir string, args ...string) bool {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	return cmd.Run() == nil
}

func gitFetch(dir string) error {
	_, err := git(dir, "fetch", "--quiet")
	return err
}

// upstreamRef returns the tracking ref (e.g. "origin/master"), or "" if none.
func upstreamRef(dir string) string {
	ref, err := git(dir, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
	if err != nil {
		return ""
	}
	return ref
}

// analyzeMerge classifies what pulling the upstream would do, without mutating.
// For an incoming merge it also checks whether dirty tracked files would block
// it; blockers lists those paths when the status is mergeDirty.
func analyzeMerge(dir string) (mergeStatus, []string) {
	if upstreamRef(dir) == "" {
		return mergeNoUpstream, nil
	}
	head, err1 := git(dir, "rev-parse", "HEAD")
	up, err2 := git(dir, "rev-parse", "@{u}")
	if err1 != nil || err2 != nil {
		return mergeNoUpstream, nil
	}
	if head == up {
		return mergeUpToDate, nil
	}

	var st mergeStatus
	switch {
	case gitOK(dir, "merge-base", "--is-ancestor", "HEAD", "@{u}"):
		st = mergeFastForward
	case gitOK(dir, "merge-base", "--is-ancestor", "@{u}", "HEAD"):
		return mergeUpToDate, nil // local is ahead; nothing incoming
	case gitOK(dir, "merge-tree", "--write-tree", "HEAD", "@{u}"):
		st = mergeClean
	default:
		return mergeConflict, nil
	}

	// An incoming merge is possible — make sure no dirty tracked file it touches
	// would be clobbered (git would refuse mid-merge otherwise).
	if blockers := mergeBlockers(dir); len(blockers) > 0 {
		return mergeDirty, blockers
	}
	return st, nil
}

// mergeBlockers returns dirty tracked files that the incoming merge would also
// change — exactly the set git refuses to overwrite.
func mergeBlockers(dir string) []string {
	dirty := dirtyTrackedFiles(dir)
	if len(dirty) == 0 {
		return nil
	}
	incoming, err := git(dir, "diff", "--name-only", "HEAD", "@{u}")
	if err != nil {
		return nil
	}
	inc := toSet(splitLines(incoming))
	var out []string
	for _, f := range dirty {
		if inc[f] {
			out = append(out, f)
		}
	}
	return out
}

func dirtyTrackedFiles(dir string) []string {
	out, err := gitRaw(dir, "status", "--porcelain", "--untracked-files=no")
	if err != nil {
		return nil
	}
	var files []string
	for _, line := range splitLines(out) {
		if len(line) < 4 {
			continue
		}
		// Porcelain v1: 2 status columns, a space, then the path.
		path := line[3:]
		// Renames show "old -> new"; the new path is what the merge cares about.
		if i := strings.Index(path, " -> "); i >= 0 {
			path = path[i+4:]
		}
		files = append(files, path)
	}
	return files
}

func splitLines(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}

// performMerge applies the upstream per the analyzed status. Caller must not
// call this for mergeConflict / mergeUpToDate / mergeNoUpstream.
func performMerge(dir string, st mergeStatus) error {
	switch st {
	case mergeFastForward:
		_, err := git(dir, "merge", "--ff-only", "@{u}")
		return err
	case mergeClean:
		_, err := git(dir, "merge", "--no-edit", "@{u}")
		if err != nil {
			// Safety net: if the real merge surprises us, leave nothing behind.
			git(dir, "merge", "--abort")
			return err
		}
		return nil
	}
	return nil
}

// fileAtRef returns the content of path as of ref, and whether it exists there.
func fileAtRef(dir, ref, path string) (string, bool) {
	out, err := git(dir, "show", ref+":"+path)
	if err != nil {
		return "", false
	}
	return out, true
}

// pathExistsAtRef reports whether path (file or dir) exists in ref's tree.
func pathExistsAtRef(dir, ref, path string) bool {
	out, err := git(dir, "ls-tree", ref, "--", path)
	return err == nil && out != ""
}
