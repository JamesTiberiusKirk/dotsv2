package main

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mattn/go-isatty"
)

// confirm shows a styled yes/no prompt and blocks for the answer. Without a TTY
// it refuses rather than guess — callers pass -y for non-interactive runs.
func confirm(question string) (bool, error) {
	if !isatty.IsTerminal(os.Stdin.Fd()) {
		return false, fmt.Errorf("not a terminal; re-run with -y to proceed non-interactively")
	}
	m := confirmModel{question: question}
	out, err := tea.NewProgram(m).Run()
	if err != nil {
		return false, err
	}
	res := out.(confirmModel)
	if res.aborted {
		return false, nil
	}
	return res.answer, nil
}

type confirmModel struct {
	question string
	answer   bool
	aborted  bool
	done     bool
}

func (m confirmModel) Init() tea.Cmd { return nil }

func (m confirmModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
		case "y", "Y":
			m.answer, m.done = true, true
			return m, tea.Quit
		case "n", "N", "esc", "q":
			m.answer, m.done = false, true
			return m, tea.Quit
		case "ctrl+c":
			m.aborted, m.done = true, true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m confirmModel) View() string {
	if m.done {
		return ""
	}
	q := lipgloss.NewStyle().Bold(true).Render(m.question)
	hint := styMuted.Render("[y/n]")
	return q + " " + hint + " "
}

// conflict resolution choices returned by promptConflict.
type choice int

const (
	choiceSkip choice = iota
	choiceLocal
	choiceRemote
)

// promptConflict asks how to resolve one conflict. note describes what is in the
// way (e.g. "→ /elsewhere" or "real file in the way"). Esc/q/n/s skip; ctrl+c
// aborts the whole run.
func promptConflict(entry, note string) (choice, error) {
	if !isatty.IsTerminal(os.Stdin.Fd()) {
		return choiceSkip, fmt.Errorf("not a terminal; --it needs an interactive terminal")
	}
	m := choiceModel{entry: entry, note: note}
	out, err := tea.NewProgram(m).Run()
	if err != nil {
		return choiceSkip, err
	}
	res := out.(choiceModel)
	if res.aborted {
		return choiceSkip, fmt.Errorf("aborted")
	}
	return res.choice, nil
}

type choiceModel struct {
	entry   string
	note    string
	choice  choice
	aborted bool
	done    bool
}

func (m choiceModel) Init() tea.Cmd { return nil }

func (m choiceModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
		case "l", "L":
			m.choice, m.done = choiceLocal, true
			return m, tea.Quit
		case "r", "R":
			m.choice, m.done = choiceRemote, true
			return m, tea.Quit
		case "s", "S", "n", "N", "esc", "q":
			m.choice, m.done = choiceSkip, true
			return m, tea.Quit
		case "ctrl+c":
			m.aborted, m.done = true, true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m choiceModel) View() string {
	if m.done {
		return ""
	}
	q := lipgloss.NewStyle().Bold(true).Render("conflict: " + m.entry)
	n := ""
	if m.note != "" {
		n = " " + styMuted.Render("("+m.note+")")
	}
	hint := styMuted.Render("[l]ocal / [r]emote / [s]kip")
	return q + n + " " + hint + " "
}

// pickHosts shows an interactive multi-select list of hosts. current is
// pre-selected. Returns the chosen subset; empty slice means aborted.
func pickHosts(all []string, current string) ([]string, error) {
	if !isatty.IsTerminal(os.Stdin.Fd()) {
		return []string{current}, nil
	}
	selected := make(map[int]bool)
	for i, h := range all {
		if h == current {
			selected[i] = true
		}
	}
	m := hostPickerModel{hosts: all, current: current, selected: selected}
	out, err := tea.NewProgram(m).Run()
	if err != nil {
		return nil, err
	}
	res := out.(hostPickerModel)
	if res.aborted {
		return nil, nil
	}
	var picked []string
	for i, h := range all {
		if res.selected[i] {
			picked = append(picked, h)
		}
	}
	return picked, nil
}

type hostPickerModel struct {
	hosts    []string
	current  string
	selected map[int]bool
	cursor   int
	aborted  bool
	done     bool
}

func (m hostPickerModel) Init() tea.Cmd { return nil }

func (m hostPickerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.hosts)-1 {
				m.cursor++
			}
		case " ":
			m.selected[m.cursor] = !m.selected[m.cursor]
		case "enter":
			m.done = true
			return m, tea.Quit
		case "ctrl+c", "q", "esc":
			m.aborted, m.done = true, true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m hostPickerModel) View() string {
	if m.done {
		return ""
	}
	var b strings.Builder
	b.WriteString(lipgloss.NewStyle().Bold(true).Render("Select hosts:") + "\n")
	for i, h := range m.hosts {
		cursor := "  "
		if m.cursor == i {
			cursor = styAdd.Render("▶ ")
		}
		box := "[ ]"
		if m.selected[i] {
			box = styAdd.Render("[x]")
		}
		name := h
		if h == m.current {
			name += styMuted.Render(" (current)")
		}
		b.WriteString(cursor + box + " " + name + "\n")
	}
	b.WriteString("\n" + styMuted.Render("↑/↓ move  space toggle  enter confirm  q abort"))
	return b.String()
}
