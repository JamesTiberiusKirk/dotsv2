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

	acts := computeActions(local, remote, f.inspect, f.src, resReport)
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

func TestComputeActionsRealFile(t *testing.T) {
	remote := []string{".vimrc"}
	f := fakeFS{
		state:    map[string]dstInfo{".vimrc": {state: stateRealFile}},
		srcThere: map[string]bool{".vimrc": true},
	}

	// Default: conflict.
	if kinds(computeActions(nil, remote, f.inspect, f.src, resReport))[".vimrc"] != actConflict {
		t.Error("real file, default -> conflict")
	}
	// --local: adopt the real file into the repo.
	if kinds(computeActions(nil, remote, f.inspect, f.src, resLocal))[".vimrc"] != actAdopt {
		t.Error("real file, --local -> adopt")
	}
	// --remote: replace with a repo link.
	if kinds(computeActions(nil, remote, f.inspect, f.src, resRemote))[".vimrc"] != actReplace {
		t.Error("real file, --remote -> replace")
	}
	// --remote but source missing upstream: cannot link -> warn.
	f.srcThere = map[string]bool{}
	if kinds(computeActions(nil, remote, f.inspect, f.src, resRemote))[".vimrc"] != actWarn {
		t.Error("real file, --remote, no src -> warn")
	}
	// --it defers: reported as conflict, resolved by the interactive pass later.
	f.srcThere = map[string]bool{".vimrc": true}
	if kinds(computeActions(nil, remote, f.inspect, f.src, resInteractive))[".vimrc"] != actConflict {
		t.Error("real file, --it -> conflict (deferred)")
	}
}

func TestComputeActionsWrongLink(t *testing.T) {
	remote := []string{".config/foreign"}

	// Target exists -> --local adopts the dereferenced content.
	live := fakeFS{
		state:    map[string]dstInfo{".config/foreign": {state: stateWrongLink, target: "/elsewhere", targetExists: true}},
		srcThere: map[string]bool{".config/foreign": true},
	}
	if kinds(computeActions(nil, remote, live.inspect, live.src, resLocal))[".config/foreign"] != actAdoptLink {
		t.Error("wrong link with target, --local -> adopt-link")
	}
	if kinds(computeActions(nil, remote, live.inspect, live.src, resRemote))[".config/foreign"] != actReplace {
		t.Error("wrong link, --remote -> replace")
	}

	// Broken link (target gone), src present -> --local falls back to replace.
	broken := fakeFS{
		state:    map[string]dstInfo{".config/foreign": {state: stateWrongLink, target: "/gone", targetExists: false}},
		srcThere: map[string]bool{".config/foreign": true},
	}
	if kinds(computeActions(nil, remote, broken.inspect, broken.src, resLocal))[".config/foreign"] != actReplace {
		t.Error("broken wrong link, --local, src present -> replace")
	}
	// Broken link, no src -> nothing to adopt or link -> remove the dead link.
	broken.srcThere = map[string]bool{}
	if kinds(computeActions(nil, remote, broken.inspect, broken.src, resLocal))[".config/foreign"] != actUnlink {
		t.Error("broken wrong link, --local, no src -> unlink")
	}
}

func TestComputeActionsDangling(t *testing.T) {
	remote := []string{".config/hypr"}
	// Dangling now, but the file is present upstream -> merge restores, no action.
	f := fakeFS{
		state:    map[string]dstInfo{".config/hypr": {state: stateDangling, ours: true}},
		srcThere: map[string]bool{".config/hypr": true},
	}
	if len(computeActions(nil, remote, f.inspect, f.src, resReport)) != 0 {
		t.Error("dangling+restored should yield no action")
	}
	// Dangling and NOT upstream -> remove the dead link (never leave dangling).
	f.srcThere = map[string]bool{}
	if kinds(computeActions(nil, remote, f.inspect, f.src, resReport))[".config/hypr"] != actUnlink {
		t.Error("dangling+missing upstream should be unlinked")
	}
}
