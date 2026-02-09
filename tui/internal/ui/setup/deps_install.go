package setup

import (
	"fmt"
	"strings"

	"github.com/Brightblade42/auto-ssl/internal/runtime"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type depsStep int

const (
	depsIdle depsStep = iota
	depsRunning
	depsDone
	depsFailed
)

type DependencyInstallModel struct {
	step    depsStep
	spinner spinner.Model
	width   int
	height  int
	err     error

	statuses []runtime.DependencyStatus
	confirm  bool
}

func NewDependencyInstall() DependencyInstallModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))

	return DependencyInstallModel{
		spinner:  s,
		statuses: runtime.Doctor(),
	}
}

func (m DependencyInstallModel) SetSize(width, height int) DependencyInstallModel {
	m.width = width
	m.height = height
	return m
}

func (m DependencyInstallModel) Init() tea.Cmd {
	return nil
}

func (m DependencyInstallModel) Update(msg tea.Msg) (DependencyInstallModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			if m.step == depsIdle {
				if !m.confirm {
					m.confirm = true
					return m, nil
				}
				m.step = depsRunning
				m.err = nil
				return m, tea.Batch(m.spinner.Tick, m.runInstall())
			}
		case "r":
			m.statuses = runtime.Doctor()
			return m, nil
		}

	case depInstallResult:
		m.statuses = runtime.Doctor()
		if msg.err != nil {
			m.err = msg.err
			m.step = depsFailed
			return m, nil
		}
		m.step = depsDone
		return m, nil

	case spinner.TickMsg:
		if m.step == depsRunning {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
	}

	return m, nil
}

type depInstallResult struct {
	err error
}

func (m DependencyInstallModel) runInstall() tea.Cmd {
	return func() tea.Msg {
		if err := runtime.RequireRoot("dependency installation"); err != nil {
			return depInstallResult{err: err}
		}

		if err := runtime.InstallDependencies(true); err != nil {
			return depInstallResult{err: err}
		}
		return depInstallResult{}
	}
}

func (m DependencyInstallModel) View() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render("Install Dependencies"))
	b.WriteString("\n\n")
	b.WriteString(descStyle.Render("Install required tools for auto-ssl workflows."))
	b.WriteString("\n\n")

	for _, dep := range m.statuses {
		marker := lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Bold(true).Render("missing")
		if dep.Found {
			marker = lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Bold(true).Render("ok")
		}
		req := "optional"
		if dep.Required {
			req = "required"
		}
		b.WriteString(fmt.Sprintf("- %s [%s, %s]\n", dep.Name, marker, req))
	}

	b.WriteString("\n")
	switch m.step {
	case depsIdle:
		if !m.confirm {
			b.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("214")).Bold(true).Render("Press Enter to confirm install using sudo/package manager."))
		} else {
			b.WriteString(focusedButton.Render("[ Install Missing Dependencies ]"))
		}
	case depsRunning:
		b.WriteString(m.spinner.View() + " Installing dependencies...")
	case depsDone:
		b.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Bold(true).Render("Dependencies installed or already present."))
	case depsFailed:
		b.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Bold(true).Render("Dependency installation failed"))
		if m.err != nil {
			b.WriteString("\n" + m.err.Error())
		}
	}

	b.WriteString("\n\n")
	b.WriteString(descStyle.Render("Press 'r' to refresh checks • ESC to return"))
	return listStyle.Render(b.String())
}
