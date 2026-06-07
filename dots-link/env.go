package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Env holds the resolved locations dots-link operates on.
type Env struct {
	Home     string // $HOME
	DotsDir  string // $HOME/.dots
	Host     string // short hostname
	HostsDir string // DotsDir/hosts
	Manifest string // HostsDir/Host
	Archive  string // DotsDir/archive
}

// NewEnv builds an Env from the environment. DOTS_DIR overrides the default
// $HOME/.dots so tests can point it at a fixture.
func NewEnv() (*Env, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("resolve home: %w", err)
	}
	dots := os.Getenv("DOTS_DIR")
	if dots == "" {
		dots = filepath.Join(home, ".dots")
	}
	host, err := shortHostname()
	if err != nil {
		return nil, err
	}
	return newEnvAt(home, dots, host), nil
}

func newEnvAt(home, dots, host string) *Env {
	return &Env{
		Home:     home,
		DotsDir:  dots,
		Host:     host,
		HostsDir: filepath.Join(dots, "hosts"),
		Manifest: filepath.Join(dots, "hosts", host),
		Archive:  filepath.Join(dots, "archive"),
	}
}

func shortHostname() (string, error) {
	if h := os.Getenv("DOTS_HOST"); h != "" {
		return h, nil
	}
	h, err := os.Hostname()
	if err != nil {
		return "", fmt.Errorf("resolve hostname: %w", err)
	}
	return strings.SplitN(h, ".", 2)[0], nil
}

// src is the repo path for an entry; dst is the live $HOME path.
func (e *Env) src(entry string) string { return filepath.Join(e.DotsDir, entry) }
func (e *Env) dst(entry string) string { return filepath.Join(e.Home, entry) }
