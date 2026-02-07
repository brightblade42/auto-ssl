package app

import (
	"github.com/Brightblade42/auto-ssl/internal/config"
	"github.com/Brightblade42/auto-ssl/internal/runtime"
	"github.com/Brightblade42/auto-ssl/internal/types"
	"github.com/Brightblade42/auto-ssl/internal/ui/components"
	"github.com/Brightblade42/auto-ssl/internal/ui/manage"
	"github.com/Brightblade42/auto-ssl/internal/ui/setup"
	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Mode represents the application mode
type Mode int

const (
	ModeInitial Mode = iota
	ModeCASetup
	ModeCAManagement
	ModeServerSetup
	ModeServerManagement
	ModeClientTrust
)

// App is the main application model
type App struct {
	version string
	width   int
	height  int
	mode    Mode
	screen  types.Screen
	config  *config.Config
	runner  *runtime.Manager

	// Sub-models for different screens
	welcome      setup.WelcomeModel
	caInit       setup.CAInitModel
	caDash       manage.DashboardModel
	serverEnroll setup.ServerEnrollModel
	clientTrust  setup.ClientTrustModel
	depsInstall  setup.DependencyInstallModel
	remoteEnroll manage.RemoteEnrollModel
	backup       manage.BackupModel

	// Shared components
	header components.HeaderModel

	// Key bindings
	keys keyMap

	// Error message
	err error
}

type keyMap struct {
	Quit key.Binding
	Help key.Binding
	Back key.Binding
}

func defaultKeyMap() keyMap {
	return keyMap{
		Quit: key.NewBinding(
			key.WithKeys("q", "ctrl+c"),
			key.WithHelp("q", "quit"),
		),
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "help"),
		),
		Back: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "back"),
		),
	}
}

// New creates a new application instance
func New(version string, runner *runtime.Manager) *App {
	// Load or create config
	cfg := config.Load()

	// Detect mode based on system state
	mode := DetectMode()

	// Determine initial screen based on mode
	var screen types.Screen
	switch mode {
	case ModeCAManagement:
		screen = types.ScreenCADashboard
	case ModeServerManagement:
		screen = types.ScreenServerEnroll
	default:
		screen = types.ScreenWelcome
	}

	app := &App{
		version: version,
		mode:    mode,
		screen:  screen,
		config:  cfg,
		runner:  runner,
		keys:    defaultKeyMap(),
		header:  components.NewHeader(version, mode.String()),
	}

	// Initialize sub-models
	app.welcome = setup.NewWelcome()
	app.caInit = setup.NewCAInit(cfg, runner)
	app.caDash = manage.NewDashboard(cfg)
	app.serverEnroll = setup.NewServerEnroll(cfg, runner)
	app.clientTrust = setup.NewClientTrust(cfg, runner)
	app.depsInstall = setup.NewDependencyInstall()
	app.remoteEnroll = manage.NewRemoteEnroll(cfg, runner)
	app.backup = manage.NewBackup(cfg, runner)

	return app
}

// Init implements tea.Model
func (a *App) Init() tea.Cmd {
	// Initialize the current screen
	switch a.screen {
	case types.ScreenWelcome:
		return a.welcome.Init()
	case types.ScreenCADashboard:
		return a.caDash.Init()
	default:
		return nil
	}
}

// Update implements tea.Model
func (a *App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Global key handlers
		switch {
		case key.Matches(msg, a.keys.Quit):
			return a, tea.Quit
		case key.Matches(msg, a.keys.Back):
			if a.screen != types.ScreenWelcome {
				a.screen = types.ScreenWelcome
				return a, a.welcome.Init()
			}
		}

	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		a.header = a.header.SetWidth(msg.Width)

		// Propagate to sub-models
		a.welcome = a.welcome.SetSize(msg.Width, msg.Height-4)
		a.caInit = a.caInit.SetSize(msg.Width, msg.Height-4)
		a.caDash = a.caDash.SetSize(msg.Width, msg.Height-4)
		a.serverEnroll = a.serverEnroll.SetSize(msg.Width, msg.Height-4)
		a.clientTrust = a.clientTrust.SetSize(msg.Width, msg.Height-4)
		a.depsInstall = a.depsInstall.SetSize(msg.Width, msg.Height-4)
		a.remoteEnroll = a.remoteEnroll.SetSize(msg.Width, msg.Height-4)
		a.backup = a.backup.SetSize(msg.Width, msg.Height-4)

	case types.ScreenChangeMsg:
		a.screen = msg.Screen
		return a, a.initScreen(msg.Screen)

	case types.ErrorMsg:
		a.err = msg.Err
		return a, nil
	}

	// Update current screen
	switch a.screen {
	case types.ScreenWelcome:
		a.welcome, cmd = a.welcome.Update(msg)
		cmds = append(cmds, cmd)
	case types.ScreenCAInit:
		a.caInit, cmd = a.caInit.Update(msg)
		cmds = append(cmds, cmd)
	case types.ScreenCADashboard:
		a.caDash, cmd = a.caDash.Update(msg)
		cmds = append(cmds, cmd)
	case types.ScreenServerEnroll:
		a.serverEnroll, cmd = a.serverEnroll.Update(msg)
		cmds = append(cmds, cmd)
	case types.ScreenClientTrust:
		a.clientTrust, cmd = a.clientTrust.Update(msg)
		cmds = append(cmds, cmd)
	case types.ScreenDependencyInstall:
		a.depsInstall, cmd = a.depsInstall.Update(msg)
		cmds = append(cmds, cmd)
	case types.ScreenRemoteEnroll:
		a.remoteEnroll, cmd = a.remoteEnroll.Update(msg)
		cmds = append(cmds, cmd)
	case types.ScreenBackup:
		a.backup, cmd = a.backup.Update(msg)
		cmds = append(cmds, cmd)
	}

	return a, tea.Batch(cmds...)
}

// View implements tea.Model
func (a *App) View() string {
	if a.width == 0 {
		return "Loading..."
	}

	var content string

	switch a.screen {
	case types.ScreenWelcome:
		content = a.welcome.View()
	case types.ScreenCAInit:
		content = a.caInit.View()
	case types.ScreenCADashboard:
		content = a.caDash.View()
	case types.ScreenServerEnroll:
		content = a.serverEnroll.View()
	case types.ScreenClientTrust:
		content = a.clientTrust.View()
	case types.ScreenDependencyInstall:
		content = a.depsInstall.View()
	case types.ScreenRemoteEnroll:
		content = a.remoteEnroll.View()
	case types.ScreenBackup:
		content = a.backup.View()
	default:
		content = "Unknown screen"
	}

	// Build the full view
	view := lipgloss.JoinVertical(
		lipgloss.Left,
		a.header.View(),
		content,
	)

	// Add error message if present
	if a.err != nil {
		errStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")).
			Bold(true)
		view += "\n" + errStyle.Render("Error: "+a.err.Error())
	}

	return view
}

func (a *App) initScreen(screen types.Screen) tea.Cmd {
	switch screen {
	case types.ScreenWelcome:
		return a.welcome.Init()
	case types.ScreenCAInit:
		return a.caInit.Init()
	case types.ScreenCADashboard:
		return a.caDash.Init()
	case types.ScreenServerEnroll:
		return a.serverEnroll.Init()
	case types.ScreenClientTrust:
		return a.clientTrust.Init()
	case types.ScreenDependencyInstall:
		return a.depsInstall.Init()
	case types.ScreenRemoteEnroll:
		return a.remoteEnroll.Init()
	case types.ScreenBackup:
		return a.backup.Init()
	default:
		return nil
	}
}

func (m Mode) String() string {
	switch m {
	case ModeCAManagement:
		return "CA Management"
	case ModeServerManagement:
		return "Server Management"
	case ModeCASetup:
		return "CA Setup"
	case ModeServerSetup:
		return "Server Setup"
	case ModeClientTrust:
		return "Client"
	default:
		return "Setup"
	}
}
