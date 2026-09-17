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

// Local PKGBUILD lists are read from their own files, and never mixed into the
// yay list — the two go to different commands.
func TestListedBuilds(t *testing.T) {
	dir := t.TempDir()
	ip := filepath.Join(dir, ".config/installed_packages")
	os.MkdirAll(ip, 0o755)
	os.WriteFile(filepath.Join(ip, "common.txt"), []byte("foo\n"), 0o644)
	os.WriteFile(filepath.Join(ip, "pkgbuilds-common.txt"), []byte("# local\nlibrepods-omarchy\n"), 0o644)
	os.WriteFile(filepath.Join(ip, "pkgbuilds-binstar.txt"), []byte("hostonly\n"), 0o644)

	got := listedBuilds(dir, "binstar")
	if len(got) != 2 || got[0] != "hostonly" || got[1] != "librepods-omarchy" {
		t.Fatalf("listedBuilds = %v, want [hostonly librepods-omarchy]", got)
	}
	if other := listedBuilds(dir, "nohost"); len(other) != 1 {
		t.Fatalf("listedBuilds(nohost) = %v, want just the common entry", other)
	}
	if p := listedPackages(dir, "binstar"); len(p) != 1 || p[0] != "foo" {
		t.Fatalf("listedPackages = %v, want [foo] — builds must not leak in", p)
	}
}
