package main

type actionKind int

const (
	actLink     actionKind = iota // create the symlink
	actUnlink                     // remove a stale repo-pointing symlink
	actConflict                   // something in the way; reported, not touched
	actAdopt                      // real file absorbed into repo + linked (--adopt)
	actWarn                       // listed but file missing in source; reported
)

type action struct {
	kind  actionKind
	entry string
	note  string
}

// dstInfo is the live state of $HOME/<entry>.
type dstInfo struct {
	state  linkState
	target string
	ours   bool // a symlink whose target resolves inside the repo
}

// computeActions is the pure heart of sync: given the current manifest entries,
// the desired (remote) entries, a way to inspect each live path, whether the
// source exists at the desired ref, and whether --adopt is set, it returns the
// reconcile actions. No side effects.
//
// localEntries should already include any stray repo-pointing symlinks found in
// the prune scope, so pruning catches links the manifest no longer mentions.
func computeActions(localEntries, remoteEntries []string, inspect func(string) dstInfo, srcRemote func(string) bool, adopt bool) []action {
	remoteSet := toSet(remoteEntries)
	var acts []action

	// Desired state: every remote entry should be a correct link.
	for _, e := range remoteEntries {
		d := inspect(e)
		has := srcRemote(e)
		switch d.state {
		case stateLinked:
			// already correct
		case stateDangling:
			if !has {
				acts = append(acts, action{actWarn, e, "listed but file missing in source"})
			}
			// else: merge restores the target, link stays valid
		case stateAbsent:
			if has {
				acts = append(acts, action{actLink, e, ""})
			} else {
				acts = append(acts, action{actWarn, e, "listed but file missing in source"})
			}
		case stateRealFile:
			if adopt {
				acts = append(acts, action{actAdopt, e, "real file → repo"})
			} else {
				acts = append(acts, action{actConflict, e, "real file in the way (use --adopt)"})
			}
		case stateWrongLink:
			acts = append(acts, action{actConflict, e, "→ " + d.target})
		}
	}

	// Prune: links we own whose entry is no longer desired.
	for _, e := range dedupNotIn(localEntries, remoteSet) {
		d := inspect(e)
		if d.ours {
			acts = append(acts, action{actUnlink, e, ""})
		}
	}

	return acts
}

// counts groups actions by kind for summaries.
func counts(acts []action) map[actionKind]int {
	m := map[actionKind]int{}
	for _, a := range acts {
		m[a.kind]++
	}
	return m
}

func toSet(xs []string) map[string]bool {
	s := make(map[string]bool, len(xs))
	for _, x := range xs {
		s[x] = true
	}
	return s
}

// dedupNotIn returns the unique members of xs that are not keys of set.
func dedupNotIn(xs []string, set map[string]bool) []string {
	seen := map[string]bool{}
	var out []string
	for _, x := range xs {
		if set[x] || seen[x] {
			continue
		}
		seen[x] = true
		out = append(out, x)
	}
	return out
}
