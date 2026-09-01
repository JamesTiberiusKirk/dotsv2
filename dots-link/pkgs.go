package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// Package lists this host converges against: the shared pair plus its own.
func pkgLists(host string) []string {
	return []string{
		".config/installed_packages/common.txt",
		".config/installed_packages/fonts.txt",
		".config/installed_packages/" + host + ".txt",
	}
}

func parsePkgs(content string) map[string]bool {
	set := map[string]bool{}
	for _, l := range strings.Split(content, "\n") {
		l = strings.TrimSpace(l)
		if l != "" && !strings.HasPrefix(l, "#") {
			set[l] = true
		}
	}
	return set
}

// listedPackages returns every package named in this host's lists, read from
// the working tree so uncommitted list edits count. Full set, not a merge
// delta: a list entry missing locally is offered on every run until installed,
// whichever commit added it and whoever declined it last time. Saying no just
// skips it.
func listedPackages(dir, host string) []string {
	set := map[string]bool{}
	for _, f := range pkgLists(host) {
		c, err := os.ReadFile(filepath.Join(dir, f))
		if err != nil {
			continue
		}
		for p := range parsePkgs(string(c)) {
			set[p] = true
		}
	}
	out := make([]string, 0, len(set))
	for p := range set {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

// filterInstalled drops packages the local pacman db already has.
// No pacman (mac) -> nothing to converge.
func filterInstalled(pkgs []string) []string {
	out, err := exec.Command("pacman", "-Qq").Output()
	if err != nil {
		return nil
	}
	installed := parsePkgs(string(out))
	kept := pkgs[:0:0]
	for _, p := range pkgs {
		if !installed[p] {
			kept = append(kept, p)
		}
	}
	return kept
}

func renderPkgPlan(pkgs []string) {
	if len(pkgs) == 0 {
		return
	}
	section("packages listed but not installed:")
	for _, p := range pkgs {
		fmt.Println("  " + label(styAdd, "install", p, ""))
	}
}

// installPackages offers the missing packages to yay. Interactive only: under
// --yes (install.sh) it is skipped — the converge's own package pass covers
// the same lists moments later.
func installPackages(pkgs []string, yes bool) error {
	if len(pkgs) == 0 {
		return nil
	}
	if yes {
		info("packages skipped under --yes — install.sh's package pass handles them")
		return nil
	}
	if _, err := exec.LookPath("yay"); err != nil {
		info("yay not found — install by hand: %s", strings.Join(pkgs, " "))
		return nil
	}
	ok, err := confirm(fmt.Sprintf("install %d missing package(s) with yay?", len(pkgs)))
	if err != nil {
		return err
	}
	if !ok {
		info("packages skipped")
		return nil
	}
	cmd := exec.Command("yay", append([]string{"-S", "--needed"}, pkgs...)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("yay: %w", err)
	}
	return nil
}
