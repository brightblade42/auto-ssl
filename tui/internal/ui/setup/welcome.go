package setup

import (
	"github.com/Brightblade42/auto-ssl/internal/runtime"
	"github.com/Brightblade42/auto-ssl/internal/types"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("46")).
			MarginBottom(1)

	descStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("108")).
			MarginBottom(2)

	listStyle = lipgloss.NewStyle().
			Margin(1, 2)
)

// MenuItem represents a menu option
type MenuItem struct {
	title       string
	description string
	screen      types.Screen
}

func (i MenuItem) Title() string       { return i.title }
func (i MenuItem) Description() string { return i.description }
func (i MenuItem) FilterValue() string { return i.title }

// WelcomeModel is the welcome/main menu screen
type WelcomeModel struct {
	list   list.Model
	width  int
	height int
}

// NewWelcome creates a new welcome screen
func NewWelcome() WelcomeModel {
	items := []list.Item{
		MenuItem{
			title:       "Set up Certificate Authority (CA)",
			description: "Initialize this machine as the CA server",
			screen:      types.ScreenCAInit,
		},
		MenuItem{
			title:       "Enroll this Server",
			description: "Get certificates for this server from an existing CA",
			screen:      types.ScreenServerEnroll,
		},
		MenuItem{
			title:       "Trust a CA (Client)",
			description: "Install a CA's root certificate on this machine",
			screen:      types.ScreenClientTrust,
		},
		MenuItem{
			title:       "Install Dependencies",
			description: "Install required tools (step, step-ca, curl)",
			screen:      types.ScreenDependencyInstall,
		},
	}

	delegate := list.NewDefaultDelegate()
	delegate.Styles.SelectedTitle = delegate.Styles.SelectedTitle.
		Foreground(lipgloss.Color("190")).
		BorderForeground(lipgloss.Color("46"))
	delegate.Styles.SelectedDesc = delegate.Styles.SelectedDesc.
		Foreground(lipgloss.Color("108"))

	l := list.New(items, delegate, 60, 14)
	l.Title = ""
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.SetShowHelp(false)
	l.Styles.Title = titleStyle

	return WelcomeModel{
		list: l,
	}
}

// SetSize updates the component size
func (m WelcomeModel) SetSize(width, height int) WelcomeModel {
	m.width = width
	m.height = height
	m.list.SetSize(width-4, height-8)
	return m
}

// Init implements tea.Model
func (m WelcomeModel) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model
func (m WelcomeModel) Update(msg tea.Msg) (WelcomeModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, key.NewBinding(key.WithKeys("enter"))):
			if item, ok := m.list.SelectedItem().(MenuItem); ok {
				return m, types.ChangeScreen(item.screen)
			}
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// View implements tea.Model
func (m WelcomeModel) View() string {
	title := titleStyle.Render("Welcome to auto-ssl")
	desc := descStyle.Render("INTERNAL PKI // READY // SELECT A WORKFLOW")
	rootHint := ""
	if !runtime.IsRoot() {
		rootHint = lipgloss.NewStyle().Foreground(lipgloss.Color("214")).Render("Most CA/server workflows require sudo. Rerun as: sudo auto-ssl-tui")
	}

	content := lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		desc,
		rootHint,
		m.list.View(),
	)

	return listStyle.Render(content)
}
