package setup

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"github.com/Brightblade42/auto-ssl/internal/config"
	rt "github.com/Brightblade42/auto-ssl/internal/runtime"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type caInitStep int

const (
	stepCAName caInitStep = iota
	stepCAAddress
	stepCAPassword
	stepCAConfirm
	stepCARunning
	stepCADone
)

var (
	focusedStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))
	blurredStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("243"))
	cursorStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))

	focusedButton = lipgloss.NewStyle().
			Foreground(lipgloss.Color("255")).
			Background(lipgloss.Color("39")).
			Padding(0, 2).
			MarginTop(1)

	blurredButton = lipgloss.NewStyle().
			Foreground(lipgloss.Color("243")).
			Background(lipgloss.Color("236")).
			Padding(0, 2).
			MarginTop(1)
)

// CAInitModel handles CA initialization
type CAInitModel struct {
	config      *config.Config
	step        caInitStep
	inputs      []textinput.Model
	focusIndex  int
	spinner     spinner.Model
	width       int
	height      int
	err         error
	output      string
	fingerprint string
	runner      *rt.Manager
}

// NewCAInit creates a new CA initialization screen
func NewCAInit(cfg *config.Config, runner *rt.Manager) CAInitModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))

	m := CAInitModel{
		config:  cfg,
		inputs:  make([]textinput.Model, 4),
		spinner: s,
		runner:  runner,
	}

	// CA Name input
	m.inputs[0] = textinput.New()
	m.inputs[0].Placeholder = "Internal CA"
	m.inputs[0].SetValue("Internal CA")
	m.inputs[0].Focus()
	m.inputs[0].CharLimit = 64
	m.inputs[0].Width = 40
	m.inputs[0].PromptStyle = focusedStyle
	m.inputs[0].TextStyle = focusedStyle

	// Address input
	m.inputs[1] = textinput.New()
	m.inputs[1].Placeholder = "192.168.1.100:9000"
	m.inputs[1].SetValue(getDefaultAddress())
	m.inputs[1].CharLimit = 64
	m.inputs[1].Width = 40

	// Password input
	m.inputs[2] = textinput.New()
	m.inputs[2].Placeholder = "••••••••"
	m.inputs[2].CharLimit = 128
	m.inputs[2].Width = 40
	m.inputs[2].EchoMode = textinput.EchoPassword
	m.inputs[2].EchoCharacter = '•'

	// Password confirm
	m.inputs[3] = textinput.New()
	m.inputs[3].Placeholder = "••••••••"
	m.inputs[3].CharLimit = 128
	m.inputs[3].Width = 40
	m.inputs[3].EchoMode = textinput.EchoPassword
	m.inputs[3].EchoCharacter = '•'

	return m
}

// SetSize updates the component size
func (m CAInitModel) SetSize(width, height int) CAInitModel {
	m.width = width
	m.height = height
	return m
}

// Init implements tea.Model
func (m CAInitModel) Init() tea.Cmd {
	return textinput.Blink
}

// Update implements tea.Model
func (m CAInitModel) Update(msg tea.Msg) (CAInitModel, tea.Cmd) {
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
			if m.focusIndex == len(m.inputs) {
				// Button selected - validate and proceed
				return m, m.validate()
			}
			// Move to next field
			m.focusIndex++
			if m.focusIndex > len(m.inputs) {
				m.focusIndex = 0
			}
			return m, m.updateFocus()
		}

	case validationResult:
		if msg.err != nil {
			m.err = msg.err
			return m, nil
		}
		m.step = stepCARunning
		return m, tea.Batch(m.spinner.Tick, m.runInit())

	case initResult:
		if msg.err != nil {
			m.err = msg.err
			m.step = stepCAConfirm
			return m, nil
		}
		m.fingerprint = msg.fingerprint
		m.output = msg.output
		m.step = stepCADone
		return m, nil

	case spinner.TickMsg:
		if m.step == stepCARunning {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	// Update inputs
	cmd := m.updateInputs(msg)
	return m, cmd
}

func (m *CAInitModel) updateFocus() tea.Cmd {
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

func (m *CAInitModel) updateInputs(msg tea.Msg) tea.Cmd {
	cmds := make([]tea.Cmd, len(m.inputs))

	for i := range m.inputs {
		m.inputs[i], cmds[i] = m.inputs[i].Update(msg)
	}

	return tea.Batch(cmds...)
}

type validationResult struct {
	err error
}

type initResult struct {
	fingerprint string
	output      string
	err         error
}

func (m CAInitModel) validate() tea.Cmd {
	return func() tea.Msg {
		// Validate CA name
		if strings.TrimSpace(m.inputs[0].Value()) == "" {
			return validationResult{err: fmt.Errorf("CA name is required")}
		}

		// Validate address
		addr := m.inputs[1].Value()
		if addr == "" {
			return validationResult{err: fmt.Errorf("address is required")}
		}

		// Validate password
		pw := m.inputs[2].Value()
		if len(pw) < 8 {
			return validationResult{err: fmt.Errorf("password must be at least 8 characters")}
		}

		if pw != m.inputs[3].Value() {
			return validationResult{err: fmt.Errorf("passwords do not match")}
		}

		return validationResult{}
	}
}

func (m CAInitModel) runInit() tea.Cmd {
	return func() tea.Msg {
		name := strings.TrimSpace(m.inputs[0].Value())
		address := strings.TrimSpace(m.inputs[1].Value())
		password := m.inputs[2].Value()

		tmp, err := os.CreateTemp("", "auto-ssl-ca-pw-*")
		if err != nil {
			return initResult{err: fmt.Errorf("failed to create password file: %v", err)}
		}
		tmpFile := tmp.Name()
		if _, err := tmp.WriteString(password); err != nil {
			tmp.Close()
			_ = os.Remove(tmpFile)
			return initResult{err: fmt.Errorf("failed to write password file: %v", err)}
		}
		if err := tmp.Chmod(0o600); err != nil {
			tmp.Close()
			_ = os.Remove(tmpFile)
			return initResult{err: fmt.Errorf("failed to secure password file: %v", err)}
		}
		_ = tmp.Close()

		// Run auto-ssl ca init
		args := []string{
			"ca", "init",
			"--name", name,
			"--address", address,
			"--password-file", tmpFile,
			"--non-interactive",
		}

		var out []byte
		if m.runner != nil {
			out, err = m.runner.RunCombinedOutput(args...)
		} else {
			cmd := exec.Command("auto-ssl", args...)
			out, err = cmd.CombinedOutput()
		}

		// Clean up
		_ = os.Remove(tmpFile)

		if err != nil {
			return initResult{err: fmt.Errorf("%s: %v", string(out), err)}
		}

		// Extract fingerprint from output
		fingerprint := extractFingerprint(string(out))

		return initResult{
			fingerprint: fingerprint,
			output:      string(out),
		}
	}
}

// extractFingerprint extracts the root CA fingerprint from the output
func extractFingerprint(output string) string {
	// Look for fingerprint pattern (64 hex chars)
	re := regexp.MustCompile(`[a-fA-F0-9]{64}`)
	matches := re.FindAllString(output, -1)
	if len(matches) > 0 {
		return matches[len(matches)-1] // Return last match (likely the fingerprint)
	}
	return "unknown"
}

// View implements tea.Model
func (m CAInitModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("Initialize Certificate Authority"))
	b.WriteString("\n\n")

	switch m.step {
	case stepCAName, stepCAAddress, stepCAPassword, stepCAConfirm:
		b.WriteString(descStyle.Render("Configure your new CA server."))
		b.WriteString("\n\n")

		// Input fields
		labels := []string{"CA Name:", "Address:", "Password:", "Confirm:"}
		for i, input := range m.inputs {
			b.WriteString(blurredStyle.Render(labels[i]))
			b.WriteString("\n")
			b.WriteString(input.View())
			b.WriteString("\n\n")
		}

		// Button
		button := blurredButton.Render("[ Initialize CA ]")
		if m.focusIndex == len(m.inputs) {
			button = focusedButton.Render("[ Initialize CA ]")
		}
		b.WriteString(button)

		// Error message
		if m.err != nil {
			b.WriteString("\n\n")
			b.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Render("Error: " + m.err.Error()))
		}

	case stepCARunning:
		b.WriteString("\n")
		b.WriteString(m.spinner.View())
		b.WriteString(" Initializing CA...")
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("This may take a minute..."))

	case stepCADone:
		b.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Render("✓ CA initialized successfully!"))
		b.WriteString("\n\n")
		b.WriteString("CA URL: https://" + m.inputs[1].Value())
		b.WriteString("\n\n")
		b.WriteString("Root Fingerprint:\n")
		b.WriteString(focusedStyle.Render(m.fingerprint))
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Save this fingerprint! You'll need it for server enrollment."))
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return to main menu"))
	}

	return listStyle.Render(b.String())
}

func getDefaultAddress() string {
	// Try to detect primary IP
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ":9000"
	}

	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				return ipnet.IP.String() + ":9000"
			}
		}
	}

	return ":9000"
}
