package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// archivePlan captures everything an archive will do, for preview + execution.
type archivePlan struct {
	entry     string
	manifests []string // host files that list the entry
	unlinkDst string   // live symlink to remove, or "" if none
	moveSrc   string   // repo file to move, or "" if missing
	moveDst   string   // destination under archive/
}

// buildArchivePlan resolves the input to an entry and works out the actions.
// now seeds the collision timestamp so the move destination is deterministic.
func buildArchivePlan(env *Env, input string, now time.Time) (*archivePlan, error) {
	entry, err := resolveEntry(env, input)
	if err != nil {
		return nil, err
	}

	manifestPaths, err := listHostManifests(env)
	if err != nil {
		return nil, err
	}
	var listed []string
	for _, p := range manifestPaths {
		m, ok, err := ParseManifest(p)
		if err != nil {
			return nil, err
		}
		if ok && m.Has(entry) {
			listed = append(listed, p)
		}
	}
	if len(listed) == 0 {
		return nil, fmt.Errorf("%q is not a whole manifest entry in any host", entry)
	}

	plan := &archivePlan{entry: entry, manifests: listed}

	// Live symlink into the repo (correct, dangling, or wrong-but-ours) -> unlink.
	if st, target, err := inspectDst(env, entry); err == nil {
		switch {
		case st == stateLinked || st == stateDangling:
			plan.unlinkDst = env.dst(entry)
		case st == stateWrongLink && pointsIntoRepo(env, env.dst(entry), target):
			plan.unlinkDst = env.dst(entry)
		}
	}

	// Repo file to move (skip if already gone).
	if exists(env.src(entry)) {
		plan.moveSrc = env.src(entry)
		dst := filepath.Join(env.Archive, entry)
		if exists(dst) {
			dst = dst + "." + now.Format("2006-01-02-150405")
		}
		plan.moveDst = dst
	}

	return plan, nil
}

func (p *archivePlan) render(env *Env) string {
	var b strings.Builder
	b.WriteString(label(styRemove, "unmanage", p.entry, "") + "\n")
	for _, m := range p.manifests {
		b.WriteString(indent(label(styRemove, "drop line", "hosts/"+filepath.Base(m), ""), 2) + "\n")
	}
	if p.unlinkDst != "" {
		b.WriteString(indent(label(styRemove, "unlink", relDisplay(env, p.unlinkDst), ""), 2) + "\n")
	} else {
		b.WriteString(indent(styMuted.Render("no live symlink to unlink"), 2) + "\n")
	}
	if p.moveSrc != "" {
		b.WriteString(indent(label(styAdd, "stash", relDisplay(env, p.moveSrc), "→ "+relDisplay(env, p.moveDst)), 2) + "\n")
	} else {
		b.WriteString(indent(styMuted.Render("repo file already absent — nothing to stash"), 2) + "\n")
	}
	return b.String()
}

// runArchive previews the plan, confirms (unless yes), then executes.
func runArchive(env *Env, input string, yes bool) error {
	plan, err := buildArchivePlan(env, input, time.Now())
	if err != nil {
		return err
	}

	title("dots-link archive")
	fmt.Print(plan.render(env))

	if !yes {
		ok, err := confirm("Archive this entry?")
		if err != nil {
			return err
		}
		if !ok {
			info("aborted")
			return nil
		}
	}

	return plan.execute(env)
}

func (p *archivePlan) execute(env *Env) error {
	// 1. Unlink the live symlink before moving its target.
	if p.unlinkDst != "" {
		if err := os.Remove(p.unlinkDst); err != nil {
			return fmt.Errorf("unlink %s: %w", p.unlinkDst, err)
		}
	}
	// 2. Move the repo file into archive/.
	if p.moveSrc != "" {
		if err := os.MkdirAll(filepath.Dir(p.moveDst), 0o755); err != nil {
			return fmt.Errorf("create archive dir: %w", err)
		}
		if err := os.Rename(p.moveSrc, p.moveDst); err != nil {
			return fmt.Errorf("move to archive: %w", err)
		}
	}
	// 3. Strip the entry from every manifest that listed it.
	for _, mp := range p.manifests {
		m, ok, err := ParseManifest(mp)
		if err != nil {
			return err
		}
		if !ok {
			continue
		}
		if m.RemoveEntry(p.entry) > 0 {
			if err := m.Write(); err != nil {
				return fmt.Errorf("rewrite %s: %w", mp, err)
			}
		}
	}
	fmt.Println(styOK.Render("✓ archived " + p.entry))
	return nil
}

// relDisplay shows a path as ~/… or repo-relative for compact output.
func relDisplay(env *Env, path string) string {
	if rel, ok := relUnder(env.DotsDir, path); ok {
		return rel
	}
	if rel, ok := relUnder(env.Home, path); ok {
		return "~/" + rel
	}
	return path
}
