package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// archiveFixture: home/.dots with two host manifests both listing .config/hypr,
// the repo dir present, and the live symlink created.
func archiveFixture(t *testing.T) (*Env, string) {
	t.Helper()
	root := t.TempDir()
	home := filepath.Join(root, "home")
	dots := filepath.Join(home, ".dots")
	entry := ".config/hypr"

	mustMkdir(t, filepath.Join(dots, ".config", "hypr"))
	mustMkdir(t, filepath.Join(dots, "hosts"))
	mustMkdir(t, filepath.Join(home, ".config"))
	mustWrite(t, filepath.Join(dots, ".config", "hypr", "hyprland.conf"), "x")

	man := "# config\n.config/hypr\n.config/nvim\n"
	mustWrite(t, filepath.Join(dots, "hosts", "testhost"), man)
	mustWrite(t, filepath.Join(dots, "hosts", "otherhost"), man)

	env := newEnvAt(home, dots, "testhost")
	if err := os.Symlink(env.src(entry), env.dst(entry)); err != nil {
		t.Fatal(err)
	}
	return env, entry
}

func TestArchiveHappyPath(t *testing.T) {
	env, entry := archiveFixture(t)
	now := time.Date(2026, 6, 7, 12, 0, 0, 0, time.UTC)

	plan, err := buildArchivePlan(env, env.dst(entry), now)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.manifests) != 2 {
		t.Fatalf("manifests = %d, want 2 (all hosts)", len(plan.manifests))
	}
	if plan.unlinkDst == "" {
		t.Error("expected a symlink to unlink")
	}
	if err := plan.execute(env); err != nil {
		t.Fatal(err)
	}

	// Symlink gone.
	if exists(env.dst(entry)) {
		t.Error("symlink still present")
	}
	// File moved into archive/.
	if !exists(filepath.Join(env.Archive, entry, "hyprland.conf")) {
		t.Error("file not stashed in archive/")
	}
	if exists(env.src(entry)) {
		t.Error("repo src still present")
	}
	// Line removed from BOTH manifests.
	for _, h := range []string{"testhost", "otherhost"} {
		m, _, _ := ParseManifest(filepath.Join(env.HostsDir, h))
		if m.Has(entry) {
			t.Errorf("%s still lists %s", h, entry)
		}
		if !m.Has(".config/nvim") {
			t.Errorf("%s lost an unrelated entry", h)
		}
	}
}

func TestArchiveRejectsSubPath(t *testing.T) {
	env, _ := archiveFixture(t)
	_, err := buildArchivePlan(env, env.dst(".config/hypr")+"/hyprland.conf", time.Now())
	if err == nil {
		t.Error("expected rejection of a sub-path that is not a whole entry")
	}
}

func TestArchiveTimestampOnCollision(t *testing.T) {
	env, entry := archiveFixture(t)
	// Pre-create the archive destination so the plan must timestamp.
	mustMkdir(t, filepath.Join(env.Archive, entry))
	now := time.Date(2026, 6, 7, 12, 0, 0, 0, time.UTC)

	plan, err := buildArchivePlan(env, env.src(entry), now)
	if err != nil {
		t.Fatal(err)
	}
	wantSuffix := ".2026-06-07-120000"
	if filepath.Base(plan.moveDst) != "hypr"+wantSuffix {
		t.Errorf("moveDst = %s, want timestamped", plan.moveDst)
	}
}

func TestArchiveNoSymlinkStillWorks(t *testing.T) {
	env, entry := archiveFixture(t)
	// Remove the live symlink: archive should still clean manifests + move file.
	if err := os.Remove(env.dst(entry)); err != nil {
		t.Fatal(err)
	}
	plan, err := buildArchivePlan(env, env.src(entry), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if plan.unlinkDst != "" {
		t.Error("no symlink expected")
	}
	if err := plan.execute(env); err != nil {
		t.Fatal(err)
	}
	if exists(env.src(entry)) {
		t.Error("file not moved")
	}
}

func mustMkdir(t *testing.T, p string) {
	t.Helper()
	if err := os.MkdirAll(p, 0o755); err != nil {
		t.Fatal(err)
	}
}

func mustWrite(t *testing.T, p, content string) {
	t.Helper()
	mustMkdir(t, filepath.Dir(p))
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
