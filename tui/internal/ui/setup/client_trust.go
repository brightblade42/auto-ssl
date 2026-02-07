package setup

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/Brightblade42/auto-ssl/internal/config"
	rt "github.com/Brightblade42/auto-ssl/internal/runtime"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type clientTrustStep int

const (
	stepClientInput clientTrustStep = iota
	stepClientRunning
	stepClientDone
	stepClientError
)

// ClientTrustModel handles client trust installation
type ClientTrustModel struct {
	config     *config.Config
	step       clientTrustStep
	inputs     []textinput.Model
	focusIndex int
	spinner    spinner.Model
	width      int
	height     int
	err        error
	platform   string
	runner     *rt.Manager
}

// NewClientTrust creates a new client trust screen
func NewClientTrust(cfg *config.Config, runner *rt.Manager) ClientTrustModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))

	m := ClientTrustModel{
		config:   cfg,
		inputs:   make([]textinput.Model, 2),
		spinner:  s,
		platform: detectPlatform(),
		runner:   runner,
	}

	// CA URL input
	m.inputs[0] = textinput.New()
	m.inputs[0].Placeholder = "https://192.168.1.100:9000"
	if cfg.CA.URL != "" {
		m.inputs[0].SetValue(cfg.CA.URL)
	}
	m.inputs[0].Focus()
	m.inputs[0].CharLimit = 128
	m.inputs[0].Width = 50
	m.inputs[0].PromptStyle = focusedStyle
	m.inputs[0].TextStyle = focusedStyle

	// Fingerprint input
	m.inputs[1] = textinput.New()
	m.inputs[1].Placeholder = "abc123def456..."
	if cfg.CA.Fingerprint != "" {
		m.inputs[1].SetValue(cfg.CA.Fingerprint)
	}
	m.inputs[1].CharLimit = 128
	m.inputs[1].Width = 50

	return m
}

// SetSize updates the component size
func (m ClientTrustModel) SetSize(width, height int) ClientTrustModel {
	m.width = width
	m.height = height
	return m
}

// Init implements tea.Model
func (m ClientTrustModel) Init() tea.Cmd {
	return textinput.Blink
}

// Update implements tea.Model
func (m ClientTrustModel) Update(msg tea.Msg) (ClientTrustModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "tab", "shift+tab", "up", "down":
			s := msg.String()
			if s == "up" || s == "shift+tab" {
				m.focusIndex--
			} else {
				m.focusIndex++
			}
			if m.focusIndex > len(m.inputs) {
				m.focusIndex = 0
			} else if m.focusIndex < 0 {
				m.focusIndex = len(m.inputs)
			}
			return m, m.updateFocus()

		case "enter":
			if m.focusIndex == len(m.inputs) && m.step == stepClientInput {
				if err := m.validate(); err != nil {
					m.err = err
					return m, nil
				}
				m.step = stepClientRunning
				return m, tea.Batch(m.spinner.Tick, m.runTrust())
			}
		}

	case clientTrustResult:
		if msg.err != nil {
			m.err = msg.err
			m.step = stepClientError
		} else {
			m.step = stepClientDone
		}
		return m, nil

	case spinner.TickMsg:
		if m.step == stepClientRunning {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	cmd := m.updateInputs(msg)
	return m, cmd
}

func (m *ClientTrustModel) updateFocus() tea.Cmd {
	cmds := make([]tea.Cmd, len(m.inputs))
	for i := 0; i < len(m.inputs); i++ {
		if i == m.focusIndex {
			cmds[i] = m.inputs[i].Focus()
			m.inputs[i].PromptStyle = focusedStyle
			m.inputs[i].TextStyle = focusedStyle
		} else {
			m.inputs[i].Blur()
			m.inputs[i].PromptStyle = blurredStyle
			m.inputs[i].TextStyle = blurredStyle
		}
	}
	return tea.Batch(cmds...)
}

func (m *ClientTrustModel) updateInputs(msg tea.Msg) tea.Cmd {
	cmds := make([]tea.Cmd, len(m.inputs))
	for i := range m.inputs {
		m.inputs[i], cmds[i] = m.inputs[i].Update(msg)
	}
	return tea.Batch(cmds...)
}

func (m ClientTrustModel) validate() error {
	caURL := strings.TrimSpace(m.inputs[0].Value())
	if caURL == "" {
		return fmt.Errorf("CA URL is required")
	}

	fingerprint := strings.TrimSpace(m.inputs[1].Value())
	if fingerprint == "" {
		return fmt.Errorf("fingerprint is required")
	}

	return nil
}

type clientTrustResult struct {
	err error
}

func (m ClientTrustModel) runTrust() tea.Cmd {
	return func() tea.Msg {
		caURL := strings.TrimSpace(m.inputs[0].Value())
		fingerprint := strings.TrimSpace(m.inputs[1].Value())

		// Run auto-ssl client trust
		args := []string{
			"client", "trust",
			"--ca-url", caURL,
			"--fingerprint", fingerprint,
		}

		var (
			out []byte
			err error
		)
		if m.runner != nil {
			out, err = m.runner.RunCombinedOutput(args...)
		} else {
			cmd := exec.Command("auto-ssl", args...)
			out, err = cmd.CombinedOutput()
		}

		if err != nil {
			return clientTrustResult{err: fmt.Errorf("%s: %v", string(out), err)}
		}

		// Small delay to ensure trust store is updated
		time.Sleep(500 * time.Millisecond)

		return clientTrustResult{}
	}
}

func detectPlatform() string {
	cmd := exec.Command("uname", "-s")
	out, err := cmd.Output()
	if err != nil {
		return "unknown"
	}

	os := strings.TrimSpace(string(out))
	switch os {
	case "Darwin":
		return "macOS (Keychain)"
	case "Linux":
		// Try to detect distro
		cmd := exec.Command("cat", "/etc/os-release")
		out, err := cmd.Output()
		if err != nil {
			return "Linux"
		}
		if strings.Contains(string(out), "rhel") ||
			strings.Contains(string(out), "fedora") ||
			strings.Contains(string(out), "centos") {
			return "Linux (RHEL/Fedora)"
		}
		if strings.Contains(string(out), "ubuntu") ||
			strings.Contains(string(out), "debian") {
			return "Linux (Ubuntu/Debian)"
		}
		return "Linux"
	default:
		return os
	}
}

// View implements tea.Model
func (m ClientTrustModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("Trust CA (Client Setup)"))
	b.WriteString("\n\n")

	switch m.step {
	case stepClientInput:
		b.WriteString(descStyle.Render("Install the root CA certificate to trust HTTPS from internal servers."))
		b.WriteString("\n\n")

		b.WriteString(blurredStyle.Render("Detected Platform: "))
		b.WriteString(m.platform)
		b.WriteString("\n\n")

		labels := []string{"CA URL:", "Fingerprint:"}
		for i, input := range m.inputs {
			b.WriteString(blurredStyle.Render(labels[i]))
			b.WriteString("\n")
			b.WriteString(input.View())
			b.WriteString("\n\n")
		}

		button := blurredButton.Render("[ Install Trust ]")
		if m.focusIndex == len(m.inputs) {
			button = focusedButton.Render("[ Install Trust ]")
		}
		b.WriteString(button)

		if m.err != nil {
			b.WriteString("\n\n")
			errStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
			b.WriteString(errStyle.Render("Error: " + m.err.Error()))
		}

	case stepClientRunning:
		b.WriteString("\n")
		b.WriteString(m.spinner.View())
		b.WriteString(" Installing root CA certificate...")
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Downloading and installing to system trust store..."))

	case stepClientDone:
		successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Bold(true)
		b.WriteString(successStyle.Render("Root CA trusted successfully!"))
		b.WriteString("\n\n")
		b.WriteString("Platform: " + m.platform + "\n")
		b.WriteString("\n")
		b.WriteString(descStyle.Render("Browsers and applications should now trust certificates from this CA."))
		b.WriteString("\n")
		b.WriteString(descStyle.Render("You may need to restart your browser for changes to take effect."))
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return"))

	case stepClientError:
		errStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Bold(true)
		b.WriteString(errStyle.Render("Trust installation failed"))
		b.WriteString("\n\n")
		if m.err != nil {
			b.WriteString(m.err.Error())
		}
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("You may need to run this with sudo/administrator privileges."))
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return"))
	}

	return listStyle.Render(b.String())
}
