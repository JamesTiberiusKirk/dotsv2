package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type syncOpts struct {
	dryRun     bool
	yes        bool
	resolution resolution
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
		return dstInfo{state: s, target: target, ours: ours, targetExists: linkTargetExists(env, e, s, target)}
	}
	srcRemote := func(e string) bool {
		if local {
			return exists(env.src(e))
		}
		return pathExistsAtRef(dir, desiredRef, e)
	}
	acts := computeActions(localEntries, remoteEntries, inspect, srcRemote, opts.resolution)

	// 6a. Interactive resolution turns each reported conflict into a concrete
	// action (or drops it on skip). Skip when dry-running — show conflicts as-is.
	if opts.resolution == resInteractive && !opts.dryRun {
		acts, err = resolveInteractive(acts, inspect, srcRemote)
		if err != nil {
			return err
		}
	}

	// 6b. Render.
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
		case actLink, actReplace:
			// Never create a dangling link: the source must really be present
			// post-merge (a local uncommitted move can defeat the ref check).
			if !exists(env.src(a.entry)) {
				fmt.Println("  " + label(styWarn, "skipped", a.entry, "source missing in repo"))
				continue
			}
			if a.kind == actReplace {
				if err := replaceWithLink(env, a.entry); err != nil {
					return err
				}
				fmt.Println("  " + label(styAdd, "replaced", a.entry, ""))
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
		case actAdoptLink:
			if err := adoptLink(env, a.entry); err != nil {
				return err
			}
			fmt.Println("  " + label(styAdd, "adopted-link", a.entry, ""))
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

// adoptLink absorbs a wrong symlink: it copies the link target's content into
// the repo source (uncommitted, for review), removes the link, and re-links the
// entry at the repo source.
func adoptLink(env *Env, entry string) error {
	dst := env.dst(entry)
	target, err := os.Readlink(dst)
	if err != nil {
		return fmt.Errorf("adopt-link %s: %w", entry, err)
	}
	abs := target
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(filepath.Dir(dst), abs)
	}
	src := env.src(entry)
	if err := os.MkdirAll(filepath.Dir(src), 0o755); err != nil {
		return err
	}
	if exists(src) {
		if err := os.RemoveAll(src); err != nil {
			return fmt.Errorf("adopt-link %s: %w", entry, err)
		}
	}
	if err := copyTree(abs, src); err != nil {
		return fmt.Errorf("adopt-link %s: %w", entry, err)
	}
	if err := os.Remove(dst); err != nil {
		return fmt.Errorf("adopt-link %s: %w", entry, err)
	}
	return makeLink(env, entry)
}

// replaceWithLink removes whatever real file or symlink occupies the entry's
// live path and creates a fresh link into the repo (repo wins).
func replaceWithLink(env *Env, entry string) error {
	if err := os.RemoveAll(env.dst(entry)); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("replace %s: %w", entry, err)
	}
	return makeLink(env, entry)
}

// copyTree recursively copies src to dst, following symlinks to their content.
func copyTree(src, dst string) error {
	fi, err := os.Stat(src)
	if err != nil {
		return err
	}
	if fi.IsDir() {
		if err := os.MkdirAll(dst, 0o755); err != nil {
			return err
		}
		ents, err := os.ReadDir(src)
		if err != nil {
			return err
		}
		for _, e := range ents {
			if err := copyTree(filepath.Join(src, e.Name()), filepath.Join(dst, e.Name())); err != nil {
				return err
			}
		}
		return nil
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, fi.Mode().Perm())
}

// linkTargetExists reports whether a wrong link's target path exists (so there
// is content to adopt). It is meaningful only for stateWrongLink.
func linkTargetExists(env *Env, entry string, st linkState, target string) bool {
	if st != stateWrongLink {
		return false
	}
	abs := target
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(filepath.Dir(env.dst(entry)), abs)
	}
	return exists(abs)
}

// resolveInteractive prompts for each reported conflict and rewrites it into a
// concrete local/remote action, or drops it when skipped.
func resolveInteractive(acts []action, inspect func(string) dstInfo, srcRemote func(string) bool) ([]action, error) {
	var out []action
	for _, a := range acts {
		if a.kind != actConflict {
			out = append(out, a)
			continue
		}
		choice, err := promptConflict(a.entry, a.note)
		if err != nil {
			return nil, err
		}
		switch choice {
		case choiceLocal:
			k, note := conflictResolve(resLocal, inspect(a.entry), srcRemote(a.entry))
			out = append(out, action{k, a.entry, note})
		case choiceRemote:
			k, note := conflictResolve(resRemote, inspect(a.entry), srcRemote(a.entry))
			out = append(out, action{k, a.entry, note})
		case choiceSkip:
			// drop: leave the conflict untouched
		}
	}
	return out, nil
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
		{actAdoptLink, "adopt-link", func(t, e, n string) string { return label(styAdd, t, e, n) }},
		{actReplace, "replace", func(t, e, n string) string { return label(styAdd, t, e, n) }},
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
	info("%d link · %d replace · %d unlink · %d adopt · %d adopt-link · %d conflict · %d warning",
		c[actLink], c[actReplace], c[actUnlink], c[actAdopt], c[actAdoptLink], c[actConflict], c[actWarn])
}
