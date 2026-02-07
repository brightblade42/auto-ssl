package manage

import (
	"fmt"
	"os"
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

type backupStep int

const (
	stepBackupConfig backupStep = iota
	stepBackupRunning
	stepBackupDone
	stepBackupError
)

// BackupModel handles CA backup
type BackupModel struct {
	config     *config.Config
	step       backupStep
	inputs     []textinput.Model
	focusIndex int
	spinner    spinner.Model
	width      int
	height     int
	err        error
	output     string
	backupPath string
	runner     *rt.Manager
}

// NewBackup creates a new backup screen
func NewBackup(cfg *config.Config, runner *rt.Manager) BackupModel {
	m := BackupModel{
		config: cfg,
		inputs: make([]textinput.Model, 2),
		runner: runner,
	}

	// Output path input
	m.inputs[0] = textinput.New()
	m.inputs[0].Placeholder = "/var/backups/auto-ssl/ca-backup.enc"
	m.inputs[0].SetValue(fmt.Sprintf("/var/backups/auto-ssl/ca-backup-%s.enc", time.Now().Format("2006-01-02")))
	m.inputs[0].Focus()
	m.inputs[0].CharLimit = 256
	m.inputs[0].Width = 50
	m.inputs[0].PromptStyle = focusedStyle
	m.inputs[0].TextStyle = focusedStyle

	// Passphrase input
	m.inputs[1] = textinput.New()
	m.inputs[1].Placeholder = "Encryption passphrase"
	m.inputs[1].CharLimit = 128
	m.inputs[1].Width = 50
	m.inputs[1].EchoMode = textinput.EchoPassword
	m.inputs[1].EchoCharacter = '*'

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))
	m.spinner = s

	return m
}

// SetSize updates the component size
func (m BackupModel) SetSize(width, height int) BackupModel {
	m.width = width
	m.height = height
	return m
}

// Init implements tea.Model
func (m BackupModel) Init() tea.Cmd {
	return textinput.Blink
}

// Update implements tea.Model
func (m BackupModel) Update(msg tea.Msg) (BackupModel, tea.Cmd) {
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
			if m.focusIndex == len(m.inputs) && m.step == stepBackupConfig {
				if err := m.validate(); err != nil {
					m.err = err
					return m, nil
				}
				m.step = stepBackupRunning
				return m, tea.Batch(m.spinner.Tick, m.runBackup())
			}
		}

	case backupResult:
		if msg.err != nil {
			m.err = msg.err
			m.step = stepBackupError
		} else {
			m.output = msg.output
			m.backupPath = msg.path
			m.step = stepBackupDone
		}
		return m, nil

	case spinner.TickMsg:
		if m.step == stepBackupRunning {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	cmd := m.updateInputs(msg)
	return m, cmd
}

func (m *BackupModel) updateFocus() tea.Cmd {
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

func (m *BackupModel) updateInputs(msg tea.Msg) tea.Cmd {
	cmds := make([]tea.Cmd, len(m.inputs))
	for i := range m.inputs {
		m.inputs[i], cmds[i] = m.inputs[i].Update(msg)
	}
	return tea.Batch(cmds...)
}

func (m BackupModel) validate() error {
	outputPath := strings.TrimSpace(m.inputs[0].Value())
	if outputPath == "" {
		return fmt.Errorf("output path is required")
	}

	passphrase := m.inputs[1].Value()
	if len(passphrase) < 8 {
		return fmt.Errorf("passphrase must be at least 8 characters")
	}

	return nil
}

type backupResult struct {
	output string
	path   string
	err    error
}

func (m BackupModel) runBackup() tea.Cmd {
	return func() tea.Msg {
		outputPath := strings.TrimSpace(m.inputs[0].Value())
		passphrase := m.inputs[1].Value()

		tmp, err := os.CreateTemp("", "auto-ssl-backup-pw-*")
		if err != nil {
			return backupResult{err: fmt.Errorf("failed to create passphrase file: %v", err)}
		}
		tmpFile := tmp.Name()
		if _, err := tmp.WriteString(passphrase); err != nil {
			tmp.Close()
			_ = os.Remove(tmpFile)
			return backupResult{err: fmt.Errorf("failed to write passphrase file: %v", err)}
		}
		if err := tmp.Chmod(0o600); err != nil {
			tmp.Close()
			_ = os.Remove(tmpFile)
			return backupResult{err: fmt.Errorf("failed to secure passphrase file: %v", err)}
		}
		_ = tmp.Close()

		// Run backup
		args := []string{"ca", "backup", "--output", outputPath, "--passphrase-file", tmpFile}
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
			return backupResult{err: fmt.Errorf("%s: %v", string(out), err)}
		}

		return backupResult{output: string(out), path: outputPath}
	}
}

// View implements tea.Model
func (m BackupModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("CA Backup"))
	b.WriteString("\n\n")

	switch m.step {
	case stepBackupConfig:
		b.WriteString(descStyle.Render("Create an encrypted backup of the CA. Store this backup securely!"))
		b.WriteString("\n\n")

		labels := []string{"Output Path:", "Passphrase:"}
		for i, input := range m.inputs {
			b.WriteString(blurredStyle.Render(labels[i]))
			b.WriteString("\n")
			b.WriteString(input.View())
			b.WriteString("\n\n")
		}

		button := blurredButton.Render("[ Create Backup ]")
		if m.focusIndex == len(m.inputs) {
			button = focusedButton.Render("[ Create Backup ]")
		}
		b.WriteString(button)

		if m.err != nil {
			b.WriteString("\n\n")
			b.WriteString(statusErrStyle.Render("Error: " + m.err.Error()))
		}

		b.WriteString("\n\n")
		b.WriteString(statusWarnStyle.Render("Warning: "))
		b.WriteString("The CA will be briefly stopped during backup.\n")

	case stepBackupRunning:
		b.WriteString("\n")
		b.WriteString(m.spinner.View())
		b.WriteString(" Creating backup...")
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Stopping CA, archiving, and encrypting..."))

	case stepBackupDone:
		b.WriteString(statusOkStyle.Render("Backup created successfully!"))
		b.WriteString("\n\n")
		b.WriteString("Backup saved to:\n")
		b.WriteString(focusedStyle.Render(m.backupPath))
		b.WriteString("\n\n")
		b.WriteString(statusWarnStyle.Render("Important: "))
		b.WriteString("Store this backup and passphrase securely!\n")
		b.WriteString("The backup contains your CA's private keys.\n")
		b.WriteString("\n")
		b.WriteString(descStyle.Render("Press ESC to return"))

	case stepBackupError:
		b.WriteString(statusErrStyle.Render("Backup failed"))
		b.WriteString("\n\n")
		if m.err != nil {
			b.WriteString(m.err.Error())
		}
		b.WriteString("\n\n")
		b.WriteString(descStyle.Render("Press ESC to return"))
	}

	return listStyle.Render(b.String())
}
