package manage

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/Brightblade42/auto-ssl/internal/config"
	rt "github.com/Brightblade42/auto-ssl/internal/runtime"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type remoteEnrollStep int

const (
	stepRemoteHost remoteEnrollStep = iota
	stepRemoteRunning
	stepRemoteDone
	stepRemoteError
)

var (
	focusedStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))
	blurredStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("243"))

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

// RemoteEnrollModel handles remote server enrollment
type RemoteEnrollModel struct {
	config     *config.Config
	step       remoteEnrollStep
	inputs     []textinput.Model
	focusIndex int
	spinner    spinner.Model
	width      int
	height     int
	err        error
	output     string
	runner     *rt.Manager
}

// NewRemoteEnroll creates a new remote enrollment screen
func NewRemoteEnroll(cfg *config.Config, runner *rt.Manager) RemoteEnrollModel {
	m := RemoteEnrollModel{
		config: cfg,
		inputs: make([]textinput.Model, 4),
		runner: runner,
	}

	// Host input
	m.inputs[0] = textinput.New()
	m.inputs[0].Placeholder = "192.168.1.50"
	m.inputs[0].Focus()
	m.inputs[0].CharLimit = 64
	m.inputs[0].Width = 40
	m.inputs[0].PromptStyle = focusedStyle
	m.inputs[0].TextStyle = focusedStyle

	// User input
	m.inputs[1] = textinput.New()
	m.inputs[1].Placeholder = "root"
	m.inputs[1].SetValue("root")
	m.inputs[1].CharLimit = 32
	m.inputs[1].Width = 40

	// Name input (optional)
	m.inputs[2] = textinput.New()
	m.inputs[2].Placeholder = "web-server-1 (optional)"
	m.inputs[2].CharLimit = 64
	m.inputs[2].Width = 40

	// Additional SANs (optional)
	m.inputs[3] = textinput.New()
	m.inputs[3].Placeholder = "myserver.local (optional)"
	m.inputs[3].CharLimit = 128
	m.inputs[3].Width = 40

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))
	m.spinner = s

	return m
}

// SetSize updates the component size
func (m RemoteEnrollModel) SetSize(width, height int) RemoteEnrollModel {
	m.width = width
	m.height = height
	return m
}

// Init implements tea.Model
func (m RemoteEnrollModel) Init() tea.Cmd {
	return textinput.Blink
}

// Update implements tea.Model
func (m RemoteEnrollModel) Update(msg tea.Msg) (RemoteEnrollModel, tea.Cmd) {
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
			if m.focusIndex == len(m.inputs) && m.step == stepRemoteHost {
				// Validate and run enrollment
				if err := m.validate(); err != nil {
					m.err = err
					return m, nil
				}
				m.step = stepRemoteRunning
				return m, tea.Batch(m.spinner.Tick, m.runEnrollment())
			}
		}

	case enrollmentResult:
		if msg.err != nil {
			m.err = msg.err
			m.step = stepRemoteError
		} else {
			m.output = msg.output
			m.step = stepRemoteDone
		}
		return m, nil

	case spinner.TickMsg:
		if m.step == stepRemoteRunning {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	cmd := m.updateInputs(msg)
	return m, cmd
}

func (m *RemoteEnrollModel) updateFocus() tea.Cmd {
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

func (m *RemoteEnrollModel) updateInputs(msg tea.Msg) tea.Cmd {
	cmds := make([]tea.Cmd, len(m.inputs))
	for i := range m.inputs {
		m.inputs[i], cmds[i] = m.inputs[i].Update(msg)
	}
	return tea.Batch(cmds...)
}

func (m RemoteEnrollModel) validate() error {
	host := strings.TrimSpace(m.inputs[0].Value())
	if host == "" {
		return fmt.Errorf("host is required")
	}

	user := strings.TrimSpace(m.inputs[1].Value())
	if user == "" {
		return fmt.Errorf("user is required")
	}

	return nil
}

type enrollmentResult struct {
	output string
	err    error
}

func (m RemoteEnrollModel) runEnrollment() tea.Cmd {
	return func() tea.Msg {
		host := strings.TrimSpace(m.inputs[0].Value())
		user := strings.TrimSpace(m.inputs[1].Value())
		name := strings.TrimSpace(m.inputs[2].Value())
		sans := strings.TrimSpace(m.inputs[3].Value())

		args := []string{"remote", "enroll", "--host", host, "--user", user}
		if name != "" {
			args = append(args, "--name", name)
		}
		if sans != "" {
			args = append(args, "--san", sans)
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
			return enrollmentResult{err: fmt.Errorf("%s: %v", string(out), err)}
		}

		return enrollmentResult{output: string(out)}
	}
}

// View implements tea.Model
func (m RemoteEnrollModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("Remote Server Enrollment"))
	b.WriteString("\n\n")

	switch m.step {
	case stepRemoteHost:
		b.WriteString(descStyle.Render("Enroll a remote server via SSH from this CA server."))
		b.WriteString("\n\n")

		labels := []string{"Host/IP:", "SSH User:", "Name:", "Additional SANs:"}
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
			b.WriteString(statusErrStyle.Render("Error: " + m.err.Error()))
		}

	case stepRemoteRunning:
		b.WriteString("\n")
		b.WriteString(m.spinner.View())
		b.WriteString(" Enrolling server " + m.inputs[0].Value() + "...")
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("This may take a minute..."))

	case stepRemoteDone:
		b.WriteString(statusOkStyle.Render("Server enrolled successfully!"))
		b.WriteString("\n\n")
		b.WriteString("Host: " + m.inputs[0].Value())
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("The server now has valid certificates and automatic renewal configured."))
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return"))

	case stepRemoteError:
		b.WriteString(statusErrStyle.Render("Enrollment failed"))
		b.WriteString("\n\n")
		if m.err != nil {
			b.WriteString(m.err.Error())
		}
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return"))
	}

	return listStyle.Render(b.String())
}
