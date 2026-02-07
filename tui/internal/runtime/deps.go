package runtime

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

type DependencyStatus struct {
	Name     string `json:"name"`
	Required bool   `json:"required"`
	Found    bool   `json:"found"`
	Path     string `json:"path,omitempty"`
	Purpose  string `json:"purpose"`
}

func Doctor() []DependencyStatus {
	deps := []DependencyStatus{
		{Name: "step", Required: true, Purpose: "certificate issuance and renewal"},
		{Name: "step-ca", Required: true, Purpose: "CA server operations"},
		{Name: "curl", Required: true, Purpose: "CA health and certificate downloads"},
		{Name: "ssh", Required: false, Purpose: "remote enrollment workflows"},
		{Name: "systemctl", Required: false, Purpose: "service and renewal timers"},
	}

	for i := range deps {
		path, err := exec.LookPath(deps[i].Name)
		if err == nil {
			deps[i].Found = true
			deps[i].Path = path
		}
	}

	return deps
}

func DoctorJSON() (string, error) {
	data, err := json.MarshalIndent(Doctor(), "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func MissingRequired(deps []DependencyStatus) []DependencyStatus {
	missing := make([]DependencyStatus, 0)
	for _, dep := range deps {
		if dep.Required && !dep.Found {
			missing = append(missing, dep)
		}
	}
	return missing
}

func InstallDependencies(autoYes bool) error {
	osName := runtime.GOOS
	if osName != "linux" && osName != "darwin" {
		return fmt.Errorf("automatic install not supported on %s", osName)
	}

	distro := detectLinuxDistro()
	pm := packageManager(osName, distro)
	if pm == "" {
		return fmt.Errorf("no supported package manager found")
	}

	deps := MissingRequired(Doctor())
	if len(deps) == 0 {
		return nil
	}

	for _, dep := range deps {
		if !autoYes {
			fmt.Printf("Install %s (%s)? [y/N]: ", dep.Name, dep.Purpose)
			var answer string
			_, _ = fmt.Scanln(&answer)
			if !strings.EqualFold(strings.TrimSpace(answer), "y") && !strings.EqualFold(strings.TrimSpace(answer), "yes") {
				continue
			}
		}

		cmd, args, err := installCommand(pm, dep.Name)
		if err != nil {
			return err
		}

		if err := runInstall(pm, dep.Name, cmd, args); err != nil {
			return fmt.Errorf("failed installing %s: %w", dep.Name, err)
		}
	}

	return nil
}

func runInstall(pm, depName, cmd string, args []string) error {
	run := func(name string, command string, commandArgs ...string) error {
		fmt.Printf("Installing %s via: %s %s\n", name, command, strings.Join(commandArgs, " "))
		installCmd := exec.Command(command, commandArgs...)
		installCmd.Stdout = os.Stdout
		installCmd.Stderr = os.Stderr
		installCmd.Stdin = os.Stdin
		return installCmd.Run()
	}

	if pm == "brew" && (depName == "step" || depName == "step-ca") {
		if err := run(depName, cmd, args...); err == nil {
			return nil
		}
		if err := run("smallstep tap", "brew", "tap", "smallstep/tap"); err != nil {
			return err
		}
		return run(depName, "brew", "install", depName)
	}

	return run(depName, cmd, args...)
}

func detectLinuxDistro() string {
	if runtime.GOOS != "linux" {
		return ""
	}

	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return ""
	}

	content := strings.ToLower(string(data))
	switch {
	case strings.Contains(content, "id=ubuntu"), strings.Contains(content, "id=debian"), strings.Contains(content, "id=pop"):
		return "debian"
	case strings.Contains(content, "id=fedora"), strings.Contains(content, "id=rhel"), strings.Contains(content, "id=centos"), strings.Contains(content, "id=rocky"), strings.Contains(content, "id=alma"):
		return "rhel"
	default:
		return ""
	}
}

func packageManager(osName, distro string) string {
	if osName == "darwin" {
		if _, err := exec.LookPath("brew"); err == nil {
			return "brew"
		}
		return ""
	}

	switch distro {
	case "debian":
		if _, err := exec.LookPath("apt-get"); err == nil {
			return "apt"
		}
	case "rhel":
		if _, err := exec.LookPath("dnf"); err == nil {
			return "dnf"
		}
		if _, err := exec.LookPath("yum"); err == nil {
			return "yum"
		}
	}

	return ""
}

func installCommand(pm, dep string) (string, []string, error) {
	switch pm {
	case "brew":
		return "brew", []string{"install", dep}, nil
	case "apt":
		pkg := dep
		if dep == "step" {
			pkg = "step-cli"
		}
		return "sudo", []string{"apt-get", "install", "-y", pkg}, nil
	case "dnf":
		pkg := dep
		if dep == "step" {
			pkg = "step-cli"
		}
		return "sudo", []string{"dnf", "install", "-y", pkg}, nil
	case "yum":
		pkg := dep
		if dep == "step" {
			pkg = "step-cli"
		}
		return "sudo", []string{"yum", "install", "-y", pkg}, nil
	default:
		return "", nil, fmt.Errorf("unsupported package manager: %s", pm)
	}
}
