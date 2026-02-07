package components

import (
	"github.com/charmbracelet/lipgloss"
)

var (
	headerStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("46")).
			Background(lipgloss.Color("16")).
			Padding(0, 2)

	modeStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("190")).
			Background(lipgloss.Color("16")).
			Padding(0, 1)

	versionStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("71")).
			Background(lipgloss.Color("16")).
			Padding(0, 2)
)

// HeaderModel represents the application header
type HeaderModel struct {
	version string
	mode    string
	width   int
}

// NewHeader creates a new header component
func NewHeader(version, mode string) HeaderModel {
	return HeaderModel{
		version: version,
		mode:    mode,
		width:   80,
	}
}

// SetWidth updates the header width
func (h HeaderModel) SetWidth(width int) HeaderModel {
	h.width = width
	return h
}

// SetMode updates the mode display
func (h HeaderModel) SetMode(mode string) HeaderModel {
	h.mode = mode
	return h
}

// View renders the header
func (h HeaderModel) View() string {
	title := headerStyle.Render("AUTO-SSL OPS CONSOLE")
	mode := modeStyle.Render("│ " + h.mode)
	version := versionStyle.Render("build " + h.version)

	// Calculate spacing
	leftPart := lipgloss.JoinHorizontal(lipgloss.Center, title, mode)
	leftWidth := lipgloss.Width(leftPart)
	rightWidth := lipgloss.Width(version)

	spaces := h.width - leftWidth - rightWidth
	if spaces < 1 {
		spaces = 1
	}

	spacer := lipgloss.NewStyle().
		Background(lipgloss.Color("16")).
		Render(repeat(" ", spaces))

	fullHeader := lipgloss.JoinHorizontal(lipgloss.Center, leftPart, spacer, version)

	return fullHeader + "\n"
}

func repeat(s string, n int) string {
	result := ""
	for i := 0; i < n; i++ {
		result += s
	}
	return result
}
