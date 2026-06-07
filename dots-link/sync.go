package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type syncOpts struct {
	dryRun bool
	yes    bool
	adopt  bool
}

func runSync(env *Env, opts syncOpts) error {
	dir := env.DotsDir
	title("dots-link sync — " + env.Host)

	// 1. Fetch (best effort; offline falls back to local reconcile).
	if err := gitFetch(dir); err != nil {
		warnLine("git fetch failed (%v) — reconciling against local state", err)
	}

	// 2. Decide the desired ref + merge plan.
	st, blockers := analyzeMerge(dir)
	ref := upstreamRef(dir)
	desiredRef := ref
	local := ref == ""
	if local {
		desiredRef = "HEAD"
	}

	// 3. Host-manifest guard: refuse if this host is gone upstream.
	hostPath := "hosts/" + env.Host
	var remoteEntries []string
	if local {
		m, err := localManifest(env)
		if err != nil {
			return err
		}
		remoteEntries = m.Entries()
	} else {
		content, ok := fileAtRef(dir, desiredRef, hostPath)
		if !ok {
			errLine("host manifest %s is missing on %s — refusing to apply.", hostPath, desiredRef)
			info("if you mean to tear down this host, run: dots-link remove")
			return fmt.Errorf("host manifest missing upstream")
		}
		remoteEntries = parseManifestBytes(hostPath, []byte(content)).Entries()
	}

	// 4. Merge-safety gate.
	section("merge: " + st.String())
	if st == mergeConflict {
		errLine("upstream would conflict — resolve by hand (git pull), then re-run sync.")
		return fmt.Errorf("merge conflict")
	}
	if st == mergeDirty {
		errLine("local uncommitted changes would be overwritten by the merge:")
		for _, b := range blockers {
			fmt.Println("  " + label(styConflict, "dirty", b, ""))
		}
		info("commit or stash them (e.g. after `archive`), then re-run sync.")
		return fmt.Errorf("dirty work tree blocks merge")
	}

	// 5. Build the action plan.
	localEntries, err := gatherLocalEntries(env)
	if err != nil {
		return err
	}
	inspect := func(e string) dstInfo {
		s, target, _ := inspectDst(env, e)
		ours := target != "" && pointsIntoRepo(env, env.dst(e), target)
		return dstInfo{state: s, target: target, ours: ours}
	}
	srcRemote := func(e string) bool {
		if local {
			return exists(env.src(e))
		}
		return pathExistsAtRef(dir, desiredRef, e)
	}
	acts := computeActions(localEntries, remoteEntries, inspect, srcRemote, opts.adopt)

	// 6. Render.
	renderSyncPlan(env, acts)

	if len(acts) == 0 && st != mergeFastForward && st != mergeClean {
		info("nothing to do")
		return nil
	}

	// 7. Dry-run stops here.
	if opts.dryRun {
		info("dry run — no changes made")
		return nil
	}

	// 8. Confirm.
	if !opts.yes {
		ok, err := confirm("Apply this plan?")
		if err != nil {
			return err
		}
		if !ok {
			info("aborted")
			return nil
		}
	}

	// 9. Execute: unlink → merge → link/adopt.
	return applySync(env, dir, st, acts)
}

func applySync(env *Env, dir string, st mergeStatus, acts []action) error {
	// Unlinks first, so no link survives pointing at a file the merge removes.
	for _, a := range acts {
		if a.kind == actUnlink {
			if err := os.Remove(env.dst(a.entry)); err != nil && !os.IsNotExist(err) {
				return fmt.Errorf("unlink %s: %w", a.entry, err)
			}
			fmt.Println("  " + label(styRemove, "unlinked", a.entry, ""))
		}
	}

	// Merge.
	if st == mergeFastForward || st == mergeClean {
		if err := performMerge(dir, st); err != nil {
			return fmt.Errorf("merge failed (no symlinks re-created): %w", err)
		}
		fmt.Println("  " + label(styAdd, "merged", st.String(), ""))
	}

	// Links / adopts after the merge, when source files are present.
	for _, a := range acts {
		switch a.kind {
		case actLink:
			// Never create a dangling link: the source must really be present
			// post-merge (a local uncommitted move can defeat the ref check).
			if !exists(env.src(a.entry)) {
				fmt.Println("  " + label(styWarn, "skipped", a.entry, "source missing in repo"))
				continue
			}
			if err := makeLink(env, a.entry); err != nil {
				return err
			}
			fmt.Println("  " + label(styAdd, "linked", a.entry, ""))
		case actAdopt:
			if err := adoptFile(env, a.entry); err != nil {
				return err
			}
			fmt.Println("  " + label(styAdd, "adopted", a.entry, ""))
		}
	}

	fmt.Println(styOK.Render("✓ sync complete"))
	return nil
}

func makeLink(env *Env, entry string) error {
	dst := env.dst(entry)
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	if err := os.Symlink(env.src(entry), dst); err != nil {
		return fmt.Errorf("link %s: %w", entry, err)
	}
	return nil
}

// adoptFile makes the live real file the source of truth: it overwrites the
// repo source with it (uncommitted, for the user to review) and links it back.
func adoptFile(env *Env, entry string) error {
	src := env.src(entry)
	if err := os.MkdirAll(filepath.Dir(src), 0o755); err != nil {
		return err
	}
	if exists(src) {
		if err := os.RemoveAll(src); err != nil {
			return fmt.Errorf("adopt %s: %w", entry, err)
		}
	}
	if err := os.Rename(env.dst(entry), src); err != nil {
		return fmt.Errorf("adopt %s: %w", entry, err)
	}
	return makeLink(env, entry)
}

// gatherLocalEntries = manifest entries ∪ stray repo-pointing links in scope.
func gatherLocalEntries(env *Env) ([]string, error) {
	m, err := localManifest(env)
	if err != nil {
		return nil, err
	}
	entries := append([]string{}, m.Entries()...)
	strays, err := scanStrayLinks(env)
	if err != nil {
		return nil, err
	}
	return append(entries, strays...), nil
}

// scanStrayLinks finds symlinks pointing into the repo within the prune scope:
// home-root dotfiles, .config/*, .scripts/*.
func scanStrayLinks(env *Env) ([]string, error) {
	var out []string
	scopes := []struct {
		dir    string
		prefix string
	}{
		{env.Home, ""},
		{filepath.Join(env.Home, ".config"), ".config"},
		{filepath.Join(env.Home, ".scripts"), ".scripts"},
	}
	for _, sc := range scopes {
		ents, err := os.ReadDir(sc.dir)
		if err != nil {
			continue // scope dir may not exist
		}
		for _, e := range ents {
			full := filepath.Join(sc.dir, e.Name())
			fi, err := os.Lstat(full)
			if err != nil || fi.Mode()&os.ModeSymlink == 0 {
				continue
			}
			target, err := os.Readlink(full)
			if err != nil || !pointsIntoRepo(env, full, target) {
				continue
			}
			entry := e.Name()
			if sc.prefix != "" {
				entry = sc.prefix + "/" + e.Name()
			}
			out = append(out, entry)
		}
	}
	return out, nil
}

func renderSyncPlan(env *Env, acts []action) {
	if len(acts) == 0 {
		info("filesystem already matches the manifest")
		return
	}
	groups := []struct {
		kind actionKind
		head string
		sty  func(tag, entry, note string) string
	}{
		{actLink, "link", func(t, e, n string) string { return label(styAdd, t, e, n) }},
		{actAdopt, "adopt", func(t, e, n string) string { return label(styAdd, t, e, n) }},
		{actUnlink, "unlink", func(t, e, n string) string { return label(styRemove, t, e, n) }},
		{actConflict, "conflict", func(t, e, n string) string { return label(styConflict, t, e, n) }},
		{actWarn, "warning", func(t, e, n string) string { return label(styWarn, t, e, n) }},
	}
	for _, g := range groups {
		var lines []string
		for _, a := range acts {
			if a.kind == g.kind {
				lines = append(lines, "  "+g.sty(g.head, a.entry, a.note))
			}
		}
		if len(lines) > 0 {
			fmt.Println(strings.Join(lines, "\n"))
		}
	}
	c := counts(acts)
	info("%d link · %d unlink · %d adopt · %d conflict · %d warning",
		c[actLink], c[actUnlink], c[actAdopt], c[actConflict], c[actWarn])
}
