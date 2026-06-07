package main

import (
	"os"
	"path/filepath"
	"testing"
)

// fixture builds a temp Home + DotsDir, with the repo file present and the
// $HOME symlink created, for entry ".config/hypr".
func fixture(t *testing.T) (*Env, string) {
	t.Helper()
	root := t.TempDir()
	home := filepath.Join(root, "home")
	dots := filepath.Join(home, ".dots")
	entry := ".config/hypr"

	if err := os.MkdirAll(filepath.Join(dots, ".config", "hypr"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(home, ".config"), 0o755); err != nil {
		t.Fatal(err)
	}
	env := newEnvAt(home, dots, "testhost")
	if err := os.Symlink(env.src(entry), env.dst(entry)); err != nil {
		t.Fatal(err)
	}
	return env, entry
}

func TestResolveFromHomeSymlink(t *testing.T) {
	env, entry := fixture(t)
	got, err := resolveEntry(env, env.dst(entry))
	if err != nil {
		t.Fatal(err)
	}
	if got != entry {
		t.Errorf("got %q, want %q", got, entry)
	}
}

func TestResolveFromRepoFile(t *testing.T) {
	env, entry := fixture(t)
	got, err := resolveEntry(env, env.src(entry))
	if err != nil {
		t.Fatal(err)
	}
	if got != entry {
		t.Errorf("got %q, want %q", got, entry)
	}
}

func TestResolveRelativeToHome(t *testing.T) {
	env, entry := fixture(t)
	// A bare relative path that exists under both home and repo.
	got, err := resolveEntry(env, entry)
	if err != nil {
		t.Fatal(err)
	}
	if got != entry {
		t.Errorf("got %q, want %q", got, entry)
	}
}

func TestResolveTilde(t *testing.T) {
	env, entry := fixture(t)
	got, err := resolveEntry(env, "~/"+entry)
	if err != nil {
		t.Fatal(err)
	}
	if got != entry {
		t.Errorf("got %q, want %q", got, entry)
	}
}

func TestResolveOutsideErrors(t *testing.T) {
	env, _ := fixture(t)
	if _, err := resolveEntry(env, "/etc/passwd"); err == nil {
		t.Error("expected error for path outside repo/home")
	}
}

func TestInspectDstStates(t *testing.T) {
	env, entry := fixture(t)

	st, _, err := inspectDst(env, entry)
	if err != nil || st != stateLinked {
		t.Fatalf("linked: st=%v err=%v", st, err)
	}

	// Remove repo src -> dangling.
	if err := os.RemoveAll(env.src(entry)); err != nil {
		t.Fatal(err)
	}
	st, _, _ = inspectDst(env, entry)
	if st != stateDangling {
		t.Errorf("after src removal: st=%v, want dangling", st)
	}

	// Absent.
	other := ".config/nope"
	st, _, _ = inspectDst(env, other)
	if st != stateAbsent {
		t.Errorf("absent: st=%v, want absent", st)
	}

	// Real file.
	real := ".bashrc"
	if err := os.WriteFile(env.dst(real), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	st, _, _ = inspectDst(env, real)
	if st != stateRealFile {
		t.Errorf("real file: st=%v, want realFile", st)
	}
}
