package main

import "testing"

const sampleManifest = `# header comment

# shell
.profile
.zshrc

# config
.config/hypr
.config/nvim
`

func TestEntries(t *testing.T) {
	m := parseManifestBytes("h", []byte(sampleManifest))
	got := m.Entries()
	want := []string{".profile", ".zshrc", ".config/hypr", ".config/nvim"}
	if len(got) != len(want) {
		t.Fatalf("entries = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("entry %d = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestHas(t *testing.T) {
	m := parseManifestBytes("h", []byte(sampleManifest))
	if !m.Has(".config/hypr") {
		t.Error("Has(.config/hypr) = false")
	}
	if m.Has(".config/hyp") {
		t.Error("Has(.config/hyp) matched a prefix")
	}
	if m.Has("# shell") {
		t.Error("Has matched a comment")
	}
}

func TestRemoveEntryPreservesComments(t *testing.T) {
	m := parseManifestBytes("h", []byte(sampleManifest))
	if n := m.RemoveEntry(".config/hypr"); n != 1 {
		t.Fatalf("removed %d, want 1", n)
	}
	if m.Has(".config/hypr") {
		t.Error("entry still present after removal")
	}
	// Comments and the other config entry must survive.
	out := string(m.Bytes())
	for _, must := range []string{"# header comment", "# shell", "# config", ".config/nvim", ".profile"} {
		if !contains(out, must) {
			t.Errorf("rewrite dropped %q:\n%s", must, out)
		}
	}
}

func TestRemoveEntryAbsent(t *testing.T) {
	m := parseManifestBytes("h", []byte(sampleManifest))
	if n := m.RemoveEntry(".config/missing"); n != 0 {
		t.Fatalf("removed %d for absent entry, want 0", n)
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
