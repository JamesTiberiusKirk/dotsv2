package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// newPackages across a two-commit fixture repo: added line reported, removed
// and pre-existing ones not, comments ignored.
func TestNewPackages(t *testing.T) {
	dir := t.TempDir()
	run := func(args ...string) {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(),
			"GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t",
			"GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	list := filepath.Join(dir, ".config/installed_packages/common.txt")
	os.MkdirAll(filepath.Dir(list), 0o755)
	run("init", "-q")
	os.WriteFile(list, []byte("# tools\nfoo\nbar\n"), 0o644)
	run("add", "-A")
	run("commit", "-qm", "one")
	os.WriteFile(list, []byte("bar\nbaz\n"), 0o644) // foo removed, baz added
	run("add", "-A")
	run("commit", "-qm", "two")

	got := newPackages(dir, "HEAD~1", "HEAD", "nohost")
	if len(got) != 1 || got[0] != "baz" {
		t.Fatalf("newPackages = %v, want [baz]", got)
	}
}
