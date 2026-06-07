package main

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// Shared palette / styles. Every line dots-link prints goes through here so the
// CLI has one consistent look.
var (
	colAccent   = lipgloss.Color("12") // bright blue
	colOK       = lipgloss.Color("10") // green
	colAdd      = lipgloss.Color("14") // cyan
	colRemove   = lipgloss.Color("13") // magenta
	colConflict = lipgloss.Color("9")  // red
	colWarn     = lipgloss.Color("11") // yellow
	colMuted    = lipgloss.Color("8")  // grey

	styTitle = lipgloss.NewStyle().Bold(true).Foreground(colAccent).
			Padding(0, 1).Border(lipgloss.RoundedBorder()).BorderForeground(colAccent)
	stySection  = lipgloss.NewStyle().Bold(true).Foreground(colAccent)
	styOK       = lipgloss.NewStyle().Foreground(colOK)
	styAdd      = lipgloss.NewStyle().Foreground(colAdd)
	styRemove   = lipgloss.NewStyle().Foreground(colRemove)
	styConflict = lipgloss.NewStyle().Foreground(colConflict)
	styWarn     = lipgloss.NewStyle().Foreground(colWarn)
	styMuted    = lipgloss.NewStyle().Foreground(colMuted)
	styEntry    = lipgloss.NewStyle()
)

// label renders a fixed-width colored tag followed by the entry text.
func label(sty lipgloss.Style, tag, entry, note string) string {
	t := sty.Width(12).Render(tag)
	line := t + " " + styEntry.Render(entry)
	if note != "" {
		line += " " + styMuted.Render(note)
	}
	return line
}

// title prints a boxed command title.
func title(s string) { fmt.Println(styTitle.Render(s)) }

// section prints a bold accent heading.
func section(s string) { fmt.Println(stySection.Render(s)) }

// info / warnLine / errLine are one-off styled messages.
func info(format string, a ...any)     { fmt.Println(styMuted.Render(fmt.Sprintf(format, a...))) }
func warnLine(format string, a ...any) { fmt.Println(styWarn.Render(fmt.Sprintf(format, a...))) }
func errLine(format string, a ...any)  { fmt.Println(styConflict.Render(fmt.Sprintf(format, a...))) }

// indent shifts a multi-line block right by n spaces.
func indent(s string, n int) string {
	pad := strings.Repeat(" ", n)
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		if l != "" {
			lines[i] = pad + l
		}
	}
	return strings.Join(lines, "\n")
}
