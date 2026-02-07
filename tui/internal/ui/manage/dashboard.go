package manage

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/Brightblade42/auto-ssl/internal/config"
	"github.com/Brightblade42/auto-ssl/internal/types"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
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
			MarginBottom(1)

	statusOkStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("46")).
			Bold(true)

	statusWarnStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("190")).
			Bold(true)

	statusErrStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Bold(true)

	boxStyle = lipgloss.NewStyle().
			Border(lipgloss.DoubleBorder()).
			BorderForeground(lipgloss.Color("22")).
			Padding(1, 2).
			MarginBottom(1)

	listStyle = lipgloss.NewStyle().
			Margin(1, 2)
)

// DashboardMenuItem represents an action item
type DashboardMenuItem struct {
	title       string
	description string
	action      string
}

func (i DashboardMenuItem) Title() string       { return i.title }
func (i DashboardMenuItem) Description() string { return i.description }
func (i DashboardMenuItem) FilterValue() string { return i.title }

// CAStatus holds the current CA status
type CAStatus struct {
	Running     bool
	URL         string
	Name        string
	Fingerprint string
	RootExpires time.Time
	ServerCount int
	Error       error
}

// DashboardModel handles the CA management dashboard
type DashboardModel struct {
	config    *config.Config
	inventory *config.Inventory
	list      list.Model
	spinner   spinner.Model
	status    CAStatus
	loading   bool
	width     int
	height    int
	err       error
}

// NewDashboard creates a new CA dashboard screen
func NewDashboard(cfg *config.Config) DashboardModel {
	items := []list.Item{
		DashboardMenuItem{
			title:       "Remote Enroll Server",
			description: "Enroll a remote server via SSH",
			action:      "remote_enroll",
		},
		DashboardMenuItem{
			title:       "View Enrolled Servers",
			description: "List and manage enrolled servers",
			action:      "view_servers",
		},
		DashboardMenuItem{
			title:       "Backup CA",
			description: "Create encrypted backup of CA",
			action:      "backup",
		},
		DashboardMenuItem{
			title:       "CA Settings",
			description: "Configuration is managed through CLI for now",
			action:      "settings",
		},
	}

	delegate := list.NewDefaultDelegate()
	delegate.Styles.SelectedTitle = delegate.Styles.SelectedTitle.
		Foreground(lipgloss.Color("190")).
		BorderForeground(lipgloss.Color("46"))

	l := list.New(items, delegate, 60, 10)
	l.Title = "Actions"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.SetShowHelp(false)

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))

	return DashboardModel{
		config:    cfg,
		inventory: config.LoadInventory(),
		list:      l,
		spinner:   s,
		loading:   true,
	}
}

// SetSize updates the component size
func (m DashboardModel) SetSize(width, height int) DashboardModel {
	m.width = width
	m.height = height
	m.list.SetSize(width-8, height/3)
	return m
}

// Init implements tea.Model
func (m DashboardModel) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		m.loadStatus(),
	)
}

type statusLoadedMsg struct {
	status CAStatus
}

func (m DashboardModel) loadStatus() tea.Cmd {
	return func() tea.Msg {
		status := CAStatus{}

		// Check if step-ca service is running
		cmd := exec.Command("systemctl", "is-active", "step-ca")
		if err := cmd.Run(); err == nil {
			status.Running = true
		}

		// Load from config
		status.URL = m.config.CA.URL
		status.Name = m.config.CA.Name
		status.Fingerprint = m.config.CA.Fingerprint

		// Count enrolled servers
		if m.inventory != nil {
			status.ServerCount = len(m.inventory.Servers)
		}

		// Try to get root CA expiration
		cmd = exec.Command("step", "certificate", "inspect",
			"/opt/step-ca/certs/root_ca.crt",
			"--format", "json")
		if out, err := cmd.Output(); err == nil {
			// Parse JSON for expiration (simplified)
			if strings.Contains(string(out), "not_after") {
				// In real implementation, parse JSON properly
				status.RootExpires = time.Now().AddDate(10, 0, 0) // Placeholder
			}
		}

		return statusLoadedMsg{status: status}
	}
}

// Update implements tea.Model
func (m DashboardModel) Update(msg tea.Msg) (DashboardModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, key.NewBinding(key.WithKeys("enter"))):
			if item, ok := m.list.SelectedItem().(DashboardMenuItem); ok {
				switch item.action {
				case "remote_enroll":
					return m, types.ChangeScreen(types.ScreenRemoteEnroll)
				case "backup":
					return m, types.ChangeScreen(types.ScreenBackup)
				case "settings":
					m.err = fmt.Errorf("settings screen not implemented yet; use auto-ssl ca status")
					return m, nil
				}
			}
		case key.Matches(msg, key.NewBinding(key.WithKeys("r"))):
			// Refresh status
			m.loading = true
			return m, tea.Batch(m.spinner.Tick, m.loadStatus())
		}

	case statusLoadedMsg:
		m.status = msg.status
		m.loading = false
		return m, nil

	case spinner.TickMsg:
		if m.loading {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// View implements tea.Model
func (m DashboardModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("CA Dashboard"))
	b.WriteString("\n\n")

	// Status box
	statusContent := m.renderStatus()
	b.WriteString(boxStyle.Render(statusContent))
	b.WriteString("\n")

	// Action list
	b.WriteString(m.list.View())

	// Help
	b.WriteString("\n")
	b.WriteString(descStyle.Render("Press 'r' to refresh • 'q' to quit • ESC to go back"))
	if m.err != nil {
		b.WriteString("\n")
		b.WriteString(statusErrStyle.Render("Error: " + m.err.Error()))
	}

	return listStyle.Render(b.String())
}

func (m DashboardModel) renderStatus() string {
	var b strings.Builder

	if m.loading {
		b.WriteString(m.spinner.View() + " Loading CA status...")
		return b.String()
	}

	// CA Name and URL
	b.WriteString(titleStyle.Render(m.status.Name))
	b.WriteString("\n")
	b.WriteString(descStyle.Render(m.status.URL))
	b.WriteString("\n\n")

	// Service status
	b.WriteString("Service: ")
	if m.status.Running {
		b.WriteString(statusOkStyle.Render("Running"))
	} else {
		b.WriteString(statusErrStyle.Render("Stopped"))
	}
	b.WriteString("\n")

	// Enrolled servers
	b.WriteString(fmt.Sprintf("Enrolled Servers: %d\n", m.status.ServerCount))

	// Fingerprint (truncated)
	if m.status.Fingerprint != "" {
		fp := m.status.Fingerprint
		if len(fp) > 20 {
			fp = fp[:20] + "..."
		}
		b.WriteString(fmt.Sprintf("Fingerprint: %s\n", fp))
	}

	return b.String()
}
