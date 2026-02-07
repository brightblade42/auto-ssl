package app

import (
	"os"
	"os/exec"
	"path/filepath"
)

const (
	defaultStepCAPath   = "/opt/step-ca"
	defaultConfigDir    = "/etc/auto-ssl"
	defaultCertDir      = "/etc/ssl/auto-ssl"
)

// DetectMode analyzes the system state and determines the appropriate application mode
func DetectMode() Mode {
	// Check if this is a CA server
	if isCAServer() {
		return ModeCAManagement
	}
	
	// Check if this server is enrolled (has certificates)
	if isEnrolledServer() {
		return ModeServerManagement
	}
	
	// Check if step is bootstrapped but no certs yet
	if isBootstrapped() {
		return ModeServerSetup
	}
	
	// Fresh machine - show initial setup
	return ModeInitial
}

// isCAServer checks if step-ca is installed and running on this machine
func isCAServer() bool {
	// Check if step-ca config exists
	configPath := filepath.Join(defaultStepCAPath, "config", "ca.json")
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return false
	}
	
	// Check if step-ca service is running (systemd)
	cmd := exec.Command("systemctl", "is-active", "step-ca")
	if err := cmd.Run(); err == nil {
		return true
	}
	
	// Check if step-ca process is running
	cmd = exec.Command("pgrep", "-x", "step-ca")
	if err := cmd.Run(); err == nil {
		return true
	}
	
	// Config exists but not running - still treat as CA server (maybe stopped)
	return true
}

// isEnrolledServer checks if this server has valid certificates
func isEnrolledServer() bool {
	certPath := filepath.Join(defaultCertDir, "server.crt")
	keyPath := filepath.Join(defaultCertDir, "server.key")
	
	// Check if both cert and key exist
	if _, err := os.Stat(certPath); os.IsNotExist(err) {
		return false
	}
	if _, err := os.Stat(keyPath); os.IsNotExist(err) {
		return false
	}
	
	return true
}

// isBootstrapped checks if step CLI is configured to trust a CA
func isBootstrapped() bool {
	// Check user's step directory
	homeDir, err := os.UserHomeDir()
	if err == nil {
		userStepPath := filepath.Join(homeDir, ".step", "config", "defaults.json")
		if _, err := os.Stat(userStepPath); err == nil {
			return true
		}
	}
	
	// Check root's step directory
	rootStepPath := "/root/.step/config/defaults.json"
	if _, err := os.Stat(rootStepPath); err == nil {
		return true
	}
	
	return false
}

// isStepCLIInstalled checks if the step CLI is available
func isStepCLIInstalled() bool {
	_, err := exec.LookPath("step")
	return err == nil
}

// isStepCAInstalled checks if step-ca is available
func isStepCAInstalled() bool {
	_, err := exec.LookPath("step-ca")
	return err == nil
}

// GetSystemInfo returns information about the current system
type SystemInfo struct {
	OS              string
	Distro          string
	Arch            string
	StepCLIVersion  string
	StepCAVersion   string
	IsCAServer      bool
	IsEnrolled      bool
	IsBootstrapped  bool
	CAURL           string
	Fingerprint     string
}

func GetSystemInfo() SystemInfo {
	info := SystemInfo{
		IsCAServer:     isCAServer(),
		IsEnrolled:     isEnrolledServer(),
		IsBootstrapped: isBootstrapped(),
	}
	
	// Get step CLI version
	if isStepCLIInstalled() {
		cmd := exec.Command("step", "version")
		if out, err := cmd.Output(); err == nil {
			info.StepCLIVersion = string(out)
		}
	}
	
	// Get step-ca version
	if isStepCAInstalled() {
		cmd := exec.Command("step-ca", "version")
		if out, err := cmd.Output(); err == nil {
			info.StepCAVersion = string(out)
		}
	}
	
	return info
}
