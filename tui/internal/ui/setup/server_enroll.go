package setup

import (
	"fmt"
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

type serverEnrollStep int

const (
	stepServerInput serverEnrollStep = iota
	stepServerRunning
	stepServerDone
	stepServerError
)

// ServerEnrollModel handles server enrollment
type ServerEnrollModel struct {
	config     *config.Config
	step       serverEnrollStep
	inputs     []textinput.Model
	focusIndex int
	spinner    spinner.Model
	width      int
	height     int
	err        error
	certPath   string
	keyPath    string
	expiry     string
	runner     *rt.Manager
}

// NewServerEnroll creates a new server enrollment screen
func NewServerEnroll(cfg *config.Config, runner *rt.Manager) ServerEnrollModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))

	m := ServerEnrollModel{
		config:  cfg,
		inputs:  make([]textinput.Model, 3),
		spinner: s,
		runner:  runner,
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

	// Password input
	m.inputs[2] = textinput.New()
	m.inputs[2].Placeholder = "Provisioner password"
	m.inputs[2].CharLimit = 128
	m.inputs[2].Width = 50
	m.inputs[2].EchoMode = textinput.EchoPassword
	m.inputs[2].EchoCharacter = '*'

	return m
}

// SetSize updates the component size
func (m ServerEnrollModel) SetSize(width, height int) ServerEnrollModel {
	m.width = width
	m.height = height
	return m
}

// Init implements tea.Model
func (m ServerEnrollModel) Init() tea.Cmd {
	return textinput.Blink
}

// Update implements tea.Model
func (m ServerEnrollModel) Update(msg tea.Msg) (ServerEnrollModel, tea.Cmd) {
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
			if m.focusIndex == len(m.inputs) && m.step == stepServerInput {
				if err := m.validate(); err != nil {
					m.err = err
					return m, nil
				}
				m.step = stepServerRunning
				return m, tea.Batch(m.spinner.Tick, m.runEnrollment())
			}
		}

	case serverEnrollResult:
		if msg.err != nil {
			m.err = msg.err
			m.step = stepServerError
		} else {
			m.certPath = msg.certPath
			m.keyPath = msg.keyPath
			m.expiry = msg.expiry
			m.step = stepServerDone
		}
		return m, nil

	case spinner.TickMsg:
		if m.step == stepServerRunning {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	cmd := m.updateInputs(msg)
	return m, cmd
}

func (m *ServerEnrollModel) updateFocus() tea.Cmd {
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

func (m *ServerEnrollModel) updateInputs(msg tea.Msg) tea.Cmd {
	cmds := make([]tea.Cmd, len(m.inputs))
	for i := range m.inputs {
		m.inputs[i], cmds[i] = m.inputs[i].Update(msg)
	}
	return tea.Batch(cmds...)
}

func (m ServerEnrollModel) validate() error {
	caURL := strings.TrimSpace(m.inputs[0].Value())
	if caURL == "" {
		return fmt.Errorf("CA URL is required")
	}

	fingerprint := strings.TrimSpace(m.inputs[1].Value())
	if fingerprint == "" {
		return fmt.Errorf("fingerprint is required")
	}

	password := m.inputs[2].Value()
	if password == "" {
		return fmt.Errorf("password is required")
	}

	return nil
}

type serverEnrollResult struct {
	certPath string
	keyPath  string
	expiry   string
	err      error
}

func (m ServerEnrollModel) runEnrollment() tea.Cmd {
	return func() tea.Msg {
		if err := rt.RequireRoot("server enrollment"); err != nil {
			return serverEnrollResult{err: err}
		}

		caURL := strings.TrimSpace(m.inputs[0].Value())
		fingerprint := strings.TrimSpace(m.inputs[1].Value())
		password := m.inputs[2].Value()

		tmp, err := os.CreateTemp("", "auto-ssl-enroll-pw-*")
		if err != nil {
			return serverEnrollResult{err: fmt.Errorf("failed to create password file: %v", err)}
		}
		tmpFile := tmp.Name()
		if _, err := tmp.WriteString(password); err != nil {
			tmp.Close()
			_ = os.Remove(tmpFile)
			return serverEnrollResult{err: fmt.Errorf("failed to write password file: %v", err)}
		}
		if err := tmp.Chmod(0o600); err != nil {
			tmp.Close()
			_ = os.Remove(tmpFile)
			return serverEnrollResult{err: fmt.Errorf("failed to secure password file: %v", err)}
		}
		_ = tmp.Close()

		// Run auto-ssl server enroll
		args := []string{
			"server", "enroll",
			"--ca-url", caURL,
			"--fingerprint", fingerprint,
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
			return serverEnrollResult{err: fmt.Errorf("%s: %v", string(out), err)}
		}

		// Extract certificate info from output
		certPath, keyPath, expiry := extractCertInfo(string(out))

		return serverEnrollResult{
			certPath: certPath,
			keyPath:  keyPath,
			expiry:   expiry,
		}
	}
}

func extractCertInfo(output string) (certPath, keyPath, expiry string) {
	// Default paths
	certPath = "/etc/ssl/auto-ssl/server.crt"
	keyPath = "/etc/ssl/auto-ssl/server.key"
	expiry = "unknown"

	// Try to extract from output
	if re := regexp.MustCompile(`Certificate:\s*(.+\.crt)`); re.MatchString(output) {
		if matches := re.FindStringSubmatch(output); len(matches) > 1 {
			certPath = strings.TrimSpace(matches[1])
		}
	}
	if re := regexp.MustCompile(`Private Key:\s*(.+\.key)`); re.MatchString(output) {
		if matches := re.FindStringSubmatch(output); len(matches) > 1 {
			keyPath = strings.TrimSpace(matches[1])
		}
	}
	if re := regexp.MustCompile(`Expires:\s*(.+)`); re.MatchString(output) {
		if matches := re.FindStringSubmatch(output); len(matches) > 1 {
			expiry = strings.TrimSpace(matches[1])
		}
	}

	return
}

// View implements tea.Model
func (m ServerEnrollModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("Enroll Server"))
	b.WriteString("\n\n")

	switch m.step {
	case stepServerInput:
		b.WriteString(descStyle.Render("Connect this server to an existing CA to get certificates."))
		b.WriteString("\n\n")

		labels := []string{"CA URL:", "Fingerprint:", "Password:"}
		for i, input := range m.inputs {
			b.WriteString(blurredStyle.Render(labels[i]))
			b.WriteString("\n")
			b.WriteString(input.View())
			b.WriteString("\n\n")
		}

		button := blurredButton.Render("[ Enroll Server ]")
		if m.focusIndex == len(m.inputs) {
			button = focusedButton.Render("[ Enroll Server ]")
		}
		b.WriteString(button)

		if m.err != nil {
			b.WriteString("\n\n")
			errStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
			b.WriteString(errStyle.Render("Error: " + m.err.Error()))
		}

	case stepServerRunning:
		b.WriteString("\n")
		b.WriteString(m.spinner.View())
		b.WriteString(" Enrolling server...")
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Bootstrapping trust, requesting certificate..."))

	case stepServerDone:
		successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Bold(true)
		b.WriteString(successStyle.Render("Server enrolled successfully!"))
		b.WriteString("\n\n")
		b.WriteString("Certificate: " + m.certPath + "\n")
		b.WriteString("Private Key: " + m.keyPath + "\n")
		b.WriteString("Expires:     " + m.expiry + "\n")
		b.WriteString("\n")
		b.WriteString(descStyle.Render("Use these paths in your web server configuration."))
		b.WriteString("\n")
		b.WriteString(descStyle.Render("Automatic renewal has been configured."))
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return"))

	case stepServerError:
		errStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Bold(true)
		b.WriteString(errStyle.Render("Enrollment failed"))
		b.WriteString("\n\n")
		if m.err != nil {
			b.WriteString(m.err.Error())
		}
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return"))
	}

	return listStyle.Render(b.String())
}
