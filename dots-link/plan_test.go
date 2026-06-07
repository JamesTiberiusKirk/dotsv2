package main

import "testing"

// fakeFS drives computeActions without touching disk.
type fakeFS struct {
	state    map[string]dstInfo
	srcThere map[string]bool
}

func (f fakeFS) inspect(e string) dstInfo { return f.state[e] }
func (f fakeFS) src(e string) bool        { return f.srcThere[e] }

func kinds(acts []action) map[string]actionKind {
	m := map[string]actionKind{}
	for _, a := range acts {
		m[a.entry] = a.kind
	}
	return m
}

func TestComputeActions(t *testing.T) {
	local := []string{".profile", ".zshrc", ".config/old", ".config/foreign"}
	remote := []string{".profile", ".zshrc", ".config/new", ".config/foreign", ".config/broken"}

	f := fakeFS{
		state: map[string]dstInfo{
			".profile":        {state: stateLinked},                          // ok
			".zshrc":          {state: stateAbsent},                          // -> link
			".config/old":     {state: stateLinked, target: "x", ours: true}, // pruned -> unlink
			".config/new":     {state: stateAbsent},                          // -> link
			".config/foreign": {state: stateWrongLink, target: "/elsewhere"}, // conflict
			".config/broken":  {state: stateAbsent},                          // listed, no src -> warn
		},
		srcThere: map[string]bool{
			".zshrc": true, ".config/new": true, // present upstream
			// .config/broken absent upstream
		},
	}

	acts := computeActions(local, remote, f.inspect, f.src, false)
	k := kinds(acts)

	want := map[string]actionKind{
		".zshrc":          actLink,
		".config/new":     actLink,
		".config/old":     actUnlink,
		".config/foreign": actConflict,
		".config/broken":  actWarn,
	}
	for e, wk := range want {
		if k[e] != wk {
			t.Errorf("%s: kind=%v, want %v", e, k[e], wk)
		}
	}
	if _, ok := k[".profile"]; ok {
		t.Error(".profile should produce no action (already linked)")
	}
}

func TestComputeActionsAdopt(t *testing.T) {
	remote := []string{".vimrc"}
	f := fakeFS{
		state:    map[string]dstInfo{".vimrc": {state: stateRealFile}},
		srcThere: map[string]bool{".vimrc": true},
	}

	// Without --adopt: conflict.
	if kinds(computeActions(nil, remote, f.inspect, f.src, false))[".vimrc"] != actConflict {
		t.Error("real file without adopt should be conflict")
	}
	// With --adopt: adopt.
	if kinds(computeActions(nil, remote, f.inspect, f.src, true))[".vimrc"] != actAdopt {
		t.Error("real file with adopt should be adopt")
	}
}

func TestComputeActionsDanglingRestored(t *testing.T) {
	remote := []string{".config/hypr"}
	// Dangling now, but the file is present upstream -> merge restores, no action.
	f := fakeFS{
		state:    map[string]dstInfo{".config/hypr": {state: stateDangling, ours: true}},
		srcThere: map[string]bool{".config/hypr": true},
	}
	if len(computeActions(nil, remote, f.inspect, f.src, false)) != 0 {
		t.Error("dangling+restored should yield no action")
	}
	// Dangling and NOT upstream -> warn.
	f.srcThere = map[string]bool{}
	if kinds(computeActions(nil, remote, f.inspect, f.src, false))[".config/hypr"] != actWarn {
		t.Error("dangling+missing upstream should warn")
	}
}
