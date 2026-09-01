package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// listedPackages reads the full set at a ref: comments ignored, removed
// entries gone, order sorted.
func TestListedPackages(t *testing.T) {
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

	got := listedPackages(dir, "nohost")
	if len(got) != 2 || got[0] != "bar" || got[1] != "baz" {
		t.Fatalf("listedPackages = %v, want [bar baz]", got)
	}
}
