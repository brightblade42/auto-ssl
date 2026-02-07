package types

import tea "github.com/charmbracelet/bubbletea"

// Screen represents which screen is currently displayed
type Screen int

const (
	ScreenWelcome Screen = iota
	ScreenCAInit
	ScreenCADashboard
	ScreenServerEnroll
	ScreenServerStatus
	ScreenClientTrust
	ScreenDependencyInstall
	ScreenRemoteEnroll
	ScreenBackup
	ScreenSettings
)

// Message types for screen navigation
type ScreenChangeMsg struct {
	Screen Screen
}

type ErrorMsg struct {
	Err error
}

// ChangeScreen creates a command to change to the specified screen
func ChangeScreen(screen Screen) tea.Cmd {
	return func() tea.Msg {
		return ScreenChangeMsg{Screen: screen}
	}
}
