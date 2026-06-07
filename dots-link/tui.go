package main

import (
	"fmt"
	"os"

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
