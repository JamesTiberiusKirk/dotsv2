package main

import (
	"fmt"
	"os"
	"path/filepath"
)

func runAdopt(env *Env, input string, yes bool) error {
	title("dots-link adopt — " + env.Host)

	entry, err := resolveEntry(env, input)
	if err != nil {
		return err
	}

	m, err := localManifest(env)
	if err != nil {
		return err
	}

	if m.Has(entry) {
		return fmt.Errorf("%s is already in the manifest", entry)
	}

	st, _, err := inspectDst(env, entry)
	if err != nil {
		return err
	}
	switch st {
	case stateAbsent:
		return fmt.Errorf("%s does not exist", env.dst(entry))
	case stateLinked, stateDangling, stateWrongLink:
		return fmt.Errorf("%s is already a symlink", env.dst(entry))
	}

	// Pick which hosts also get the manifest entry.
	var hosts []string
	if yes {
		hosts = []string{env.Host}
	} else {
		all, err := listHostNames(env)
		if err != nil {
			return err
		}
		hosts, err = pickHosts(all, env.Host)
		if err != nil {
			return err
		}
		if len(hosts) == 0 {
			info("aborted")
			return nil
		}
	}

	// Plan.
	section("plan")
	fmt.Println("  " + label(styAdd, "adopt", entry, ""))
	if err := printFileTree(env.dst(entry), "  "); err != nil {
		return err
	}
	// Compute tag width from the longest host name so columns stay aligned.
	maxLen := 0
	for _, h := range hosts {
		if n := len("hosts/" + h); n > maxLen {
			maxLen = n
		}
	}
	fmt.Println()
	for _, h := range hosts {
		tag := "hosts/" + h
		note := "manifest only — link on next sync"
		if h == env.Host {
			note = "move into repo, link back"
		}
		padded := styAdd.Width(maxLen + 2).Render(tag)
		fmt.Println("  " + padded + " " + styEntry.Render(entry) + " " + styMuted.Render(note))
	}

	if !yes {
		fmt.Println()
		ok, err := confirm("Apply?")
		if err != nil {
			return err
		}
		if !ok {
			info("aborted")
			return nil
		}
	}

	// Execute: current host first (moves the real file into repo).
	for _, h := range hosts {
		mp := filepath.Join(env.HostsDir, h)
		hm, ok, err := ParseManifest(mp)
		if err != nil {
			return err
		}
		if !ok {
			warnLine("manifest for host %q not found — skipping", h)
			continue
		}
		if hm.Has(entry) {
			continue
		}
		hm.Lines = append(hm.Lines, entry)
		if err := hm.Write(); err != nil {
			return fmt.Errorf("write manifest %s: %w", h, err)
		}
	}

	if err := adoptFile(env, entry); err != nil {
		return err
	}

	fmt.Println(styOK.Render("✓ adopted " + entry))
	return nil
}

// listHostNames returns the base names of every file in hosts/.
func listHostNames(env *Env) ([]string, error) {
	paths, err := listHostManifests(env)
	if err != nil {
		return nil, err
	}
	names := make([]string, len(paths))
	for i, p := range paths {
		names[i] = filepath.Base(p)
	}
	return names, nil
}

// printFileTree prints a tree rooted at path using box-drawing characters.
func printFileTree(path, indent string) error {
	fi, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !fi.IsDir() {
		return nil // single file — the label above is enough
	}
	return walkTree(path, indent, 2)
}

func walkTree(dir, indent string, depthLeft int) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for i, e := range entries {
		last := i == len(entries)-1
		branch := "├── "
		childIndent := indent + "│   "
		if last {
			branch = "└── "
			childIndent = indent + "    "
		}
		name := e.Name()
		if e.IsDir() {
			name += "/"
			if depthLeft <= 1 {
				n := countFiles(filepath.Join(dir, e.Name()))
				name += styMuted.Render(fmt.Sprintf(" (%d files)", n))
			}
		}
		fmt.Println(indent + styMuted.Render(branch) + name)
		if e.IsDir() && depthLeft > 1 {
			if err := walkTree(filepath.Join(dir, e.Name()), childIndent, depthLeft-1); err != nil {
				return err
			}
		}
	}
	return nil
}

func countFiles(dir string) int {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	n := 0
	for _, e := range entries {
		if e.IsDir() {
			n += countFiles(filepath.Join(dir, e.Name()))
		} else {
			n++
		}
	}
	return n
}

