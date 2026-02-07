package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/Brightblade42/auto-ssl/internal/app"
	"github.com/Brightblade42/auto-ssl/internal/runtime"
	tea "github.com/charmbracelet/bubbletea"
)

var (
	Version   = "dev"
	BuildTime = "unknown"
)

func main() {
	manager := runtime.NewManager(Version)

	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "--version", "-v", "version":
			fmt.Printf("auto-ssl-tui version %s (built %s)\n", Version, BuildTime)
			return
		case "dump-bash":
			if err := runDumpBash(manager, os.Args[2:]); err != nil {
				fmt.Fprintf(os.Stderr, "dump-bash failed: %v\n", err)
				os.Exit(1)
			}
			return
		case "doctor":
			if err := runDoctor(os.Args[2:]); err != nil {
				fmt.Fprintf(os.Stderr, "doctor failed: %v\n", err)
				os.Exit(1)
			}
			return
		case "install-deps":
			autoYes := false
			for _, arg := range os.Args[2:] {
				if arg == "--yes" {
					autoYes = true
				}
			}
			if err := runtime.InstallDependencies(autoYes); err != nil {
				fmt.Fprintf(os.Stderr, "install-deps failed: %v\n", err)
				os.Exit(1)
			}
			return
		case "exec":
			if err := runExec(manager, os.Args[2:]); err != nil {
				fmt.Fprintf(os.Stderr, "exec failed: %v\n", err)
				os.Exit(1)
			}
			return
		}
	}

	// Create and run the application
	application := app.New(Version, manager)
	p := tea.NewProgram(application, tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error running application: %v\n", err)
		os.Exit(1)
	}
}

func runDumpBash(manager *runtime.Manager, args []string) error {
	output := "./auto-ssl-bash"
	force := false
	printPath := false
	writeChecksum := false

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--output":
			if i+1 >= len(args) {
				return fmt.Errorf("--output requires a path")
			}
			output = args[i+1]
			i++
		case "--force":
			force = true
		case "--print-path":
			printPath = true
		case "--checksum":
			writeChecksum = true
		default:
			return fmt.Errorf("unknown option: %s", args[i])
		}
	}

	dir, err := manager.DumpBash(output, force)
	if err != nil {
		return err
	}

	if writeChecksum {
		manifest, err := checksumManifest(dir)
		if err != nil {
			return err
		}
		manifestPath := filepath.Join(dir, "CHECKSUMS.txt")
		if err := os.WriteFile(manifestPath, []byte(manifest), 0o644); err != nil {
			return err
		}
	}

	if printPath {
		fmt.Println(dir)
		return nil
	}

	fmt.Printf("Bash runtime dumped to %s\n", dir)
	return nil
}

func checksumManifest(root string) (string, error) {
	var lines []string
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		if filepath.Base(path) == "CHECKSUMS.txt" {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()
		hash := sha256.New()
		if _, err := io.Copy(hash, file); err != nil {
			return err
		}
		lines = append(lines, fmt.Sprintf("%s  %s", hex.EncodeToString(hash.Sum(nil)), rel))
		return nil
	})
	if err != nil {
		return "", err
	}
	return strings.Join(lines, "\n") + "\n", nil
}

func runDoctor(args []string) error {
	asJSON := false
	for _, arg := range args {
		if arg == "--json" {
			asJSON = true
			continue
		}
		return fmt.Errorf("unknown option: %s", arg)
	}

	if asJSON {
		out, err := runtime.DoctorJSON()
		if err != nil {
			return err
		}
		fmt.Println(out)
		return nil
	}

	deps := runtime.Doctor()
	for _, dep := range deps {
		status := "missing"
		if dep.Found {
			status = "ok"
		}
		required := "optional"
		if dep.Required {
			required = "required"
		}
		if dep.Path != "" {
			fmt.Printf("%-10s  %-8s  %-8s  %s\n", dep.Name, status, required, dep.Path)
		} else {
			fmt.Printf("%-10s  %-8s  %-8s  %s\n", dep.Name, status, required, dep.Purpose)
		}
	}
	return nil
}

func runExec(manager *runtime.Manager, args []string) error {
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}
	if len(args) == 0 {
		return fmt.Errorf("usage: auto-ssl-tui exec -- <args>")
	}
	path, err := manager.AutoSSLPath()
	if err != nil {
		return err
	}
	cmd := exec.Command(path, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}
