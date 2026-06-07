package main

import (
	"fmt"
	"os"
)

// localManifest loads this host's manifest, erroring if it is missing.
func localManifest(env *Env) (*Manifest, error) {
	m, ok, err := ParseManifest(env.Manifest)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("no manifest for host %q (expected %s)", env.Host, env.Manifest)
	}
	return m, nil
}

// runStatus prints the health of every manifest entry. Read-only.
func runStatus(env *Env) error {
	m, err := localManifest(env)
	if err != nil {
		return err
	}
	title("dots-link status — " + env.Host)
	entries := m.Entries()
	if len(entries) == 0 {
		info("manifest is empty")
		return nil
	}
	for _, entry := range entries {
		fmt.Println("  " + statusLine(env, entry))
	}
	return nil
}

func statusLine(env *Env, entry string) string {
	srcMissing := !exists(env.src(entry))
	st, target, err := inspectDst(env, entry)
	if err != nil {
		return label(styConflict, "error", entry, err.Error())
	}
	switch {
	case srcMissing && st == stateAbsent:
		return label(styConflict, "missing src", entry, "")
	case st == stateLinked:
		return label(styOK, "ok", entry, "")
	case st == stateDangling:
		return label(styConflict, "missing src", entry, "→ "+target)
	case st == stateAbsent:
		return label(styWarn, "not linked", entry, "")
	case st == stateWrongLink:
		return label(styConflict, "conflict", entry, "→ "+target)
	case st == stateRealFile:
		return label(styConflict, "conflict", entry, "(real file/dir)")
	default:
		return label(styWarn, "unknown", entry, "")
	}
}

// runRemove tears down this host's managed symlinks without touching files or
// the manifest. Only links pointing into the repo are removed.
func runRemove(env *Env) error {
	m, err := localManifest(env)
	if err != nil {
		return err
	}
	title("dots-link remove — " + env.Host)
	removed := 0
	for _, entry := range m.Entries() {
		st, target, err := inspectDst(env, entry)
		if err != nil {
			fmt.Println("  " + label(styConflict, "error", entry, err.Error()))
			continue
		}
		// Linked or dangling both point at our src -> ours to remove.
		if st == stateLinked || st == stateDangling || (st == stateWrongLink && pointsIntoRepo(env, env.dst(entry), target)) {
			if err := os.Remove(env.dst(entry)); err != nil {
				fmt.Println("  " + label(styConflict, "error", entry, err.Error()))
				continue
			}
			fmt.Println("  " + label(styRemove, "removed", entry, ""))
			removed++
		}
	}
	info("%d link(s) removed", removed)
	return nil
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}
