package main

type actionKind int

const (
	actLink      actionKind = iota // create the symlink
	actUnlink                      // remove a stale/dead repo-pointing symlink
	actConflict                    // something in the way; reported, not touched
	actAdopt                       // real file absorbed into repo + linked (--local)
	actAdoptLink                   // wrong link's target content absorbed into repo + linked (--local)
	actReplace                     // live file/link removed, replaced by a repo link (--remote)
	actWarn                        // listed but file missing in source; reported
)

// resolution is how sync handles conflicts (a real file or a wrong symlink in
// the way of a desired link).
type resolution int

const (
	resReport      resolution = iota // default: report conflicts, change nothing
	resLocal                         // local wins: absorb into the repo (--local)
	resRemote                        // repo wins: replace with a repo link (--remote)
	resInteractive                   // prompt per conflict (--it)
)

type action struct {
	kind  actionKind
	entry string
	note  string
}

// dstInfo is the live state of $HOME/<entry>.
type dstInfo struct {
	state        linkState
	target       string
	ours         bool // a symlink whose target resolves inside the repo
	targetExists bool // for a wrong link: whether its target path exists
}

// computeActions is the pure heart of sync: given the current manifest entries,
// the desired (remote) entries, a way to inspect each live path, whether the
// source exists at the desired ref, and the conflict-resolution strategy, it
// returns the reconcile actions. No side effects.
//
// localEntries should already include any stray repo-pointing symlinks found in
// the prune scope, so pruning catches links the manifest no longer mentions.
func computeActions(localEntries, remoteEntries []string, inspect func(string) dstInfo, srcRemote func(string) bool, res resolution) []action {
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
			// A dead link into the repo. If the source is present upstream the
			// merge restores it and the link is valid again — leave it. If not,
			// never leave a dangling link: remove it.
			if !has {
				acts = append(acts, action{actUnlink, e, "dead link, source gone"})
			}
		case stateAbsent:
			if has {
				acts = append(acts, action{actLink, e, ""})
			} else {
				acts = append(acts, action{actWarn, e, "listed but file missing in source"})
			}
		case stateRealFile, stateWrongLink:
			k, note := conflictResolve(res, d, has)
			acts = append(acts, action{k, e, note})
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

// conflictResolve maps a conflict (real file or wrong link in the way) plus the
// chosen strategy to a concrete action. has reports whether the repo source
// exists at the desired ref. resInteractive defers to a later prompt, so it is
// reported as a conflict here and rewritten before apply.
func conflictResolve(res resolution, d dstInfo, has bool) (actionKind, string) {
	switch res {
	case resLocal:
		switch d.state {
		case stateRealFile:
			return actAdopt, "real file → repo"
		case stateWrongLink:
			if d.targetExists {
				return actAdoptLink, "link target → repo"
			}
			// Broken link: nothing to adopt. Fall back to the dangling rule.
			if has {
				return actReplace, "dead link → repo link"
			}
			return actUnlink, "dead link, nothing to adopt"
		}
	case resRemote:
		if !has {
			return actWarn, "remote wins but file missing in source"
		}
		return actReplace, "→ repo link"
	}
	// resReport / resInteractive: report only.
	if d.state == stateWrongLink {
		return actConflict, "→ " + d.target
	}
	return actConflict, "real file in the way (use --local/--remote/--it)"
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
