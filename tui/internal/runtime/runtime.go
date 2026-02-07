package runtime

import (
	"crypto/sha256"
	"embed"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
)

//go:embed assets/bash/**
var embeddedBash embed.FS

type Manager struct {
	version string

	mu         sync.Mutex
	extractDir string
}

func NewManager(version string) *Manager {
	if strings.TrimSpace(version) == "" {
		version = "dev"
	}
	return &Manager{version: version}
}

func (m *Manager) AutoSSLPath() (string, error) {
	dir, err := m.ensureExtracted()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "auto-ssl"), nil
}

func (m *Manager) Exec(args ...string) *exec.Cmd {
	path, err := m.AutoSSLPath()
	if err != nil {
		return exec.Command("/usr/bin/env", "false")
	}
	return exec.Command(path, args...)
}

func (m *Manager) RunCombinedOutput(args ...string) ([]byte, error) {
	path, err := m.AutoSSLPath()
	if err != nil {
		return nil, err
	}
	cmd := exec.Command(path, args...)
	return cmd.CombinedOutput()
}

func (m *Manager) DumpBash(outputDir string, force bool) (string, error) {
	if strings.TrimSpace(outputDir) == "" {
		outputDir = "./auto-ssl-bash"
	}

	absOut, err := filepath.Abs(outputDir)
	if err != nil {
		return "", err
	}

	if _, err := os.Stat(absOut); err == nil {
		if !force {
			return "", fmt.Errorf("output directory already exists: %s (use --force)", absOut)
		}
		if err := os.RemoveAll(absOut); err != nil {
			return "", err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}

	if err := os.MkdirAll(absOut, 0o755); err != nil {
		return "", err
	}

	if err := copyEmbeddedTree(absOut); err != nil {
		return "", err
	}

	return absOut, nil
}

func (m *Manager) ensureExtracted() (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.extractDir != "" {
		return m.extractDir, nil
	}

	base, err := os.UserCacheDir()
	if err != nil || base == "" {
		base = os.TempDir()
	}

	root := filepath.Join(base, "auto-ssl-tui", "runtime", sanitizeVersion(m.version))
	marker := filepath.Join(root, ".extracted")

	assetHash, err := embeddedHash()
	if err != nil {
		return "", err
	}
	markerValue := m.version + "|" + assetHash

	if data, err := os.ReadFile(marker); err == nil && strings.TrimSpace(string(data)) == markerValue {
		m.extractDir = root
		return root, nil
	}

	if err := os.RemoveAll(root); err != nil {
		return "", err
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		return "", err
	}

	if err := copyEmbeddedTree(root); err != nil {
		return "", err
	}

	if err := os.WriteFile(marker, []byte(markerValue+"\n"), 0o644); err != nil {
		return "", err
	}

	_ = cleanupOldRuntimeDirs(filepath.Dir(root), filepath.Base(root))

	m.extractDir = root
	return root, nil
}

func sanitizeVersion(v string) string {
	v = strings.TrimSpace(v)
	v = strings.ReplaceAll(v, string(filepath.Separator), "-")
	v = strings.ReplaceAll(v, " ", "-")
	if v == "" {
		return "dev"
	}
	return v
}

func copyEmbeddedTree(dest string) error {
	entries, err := fs.ReadDir(embeddedBash, "assets/bash")
	if err != nil {
		return err
	}

	for _, entry := range entries {
		srcPath := filepath.ToSlash(filepath.Join("assets/bash", entry.Name()))
		destPath := filepath.Join(dest, entry.Name())
		if err := copyEmbeddedPath(srcPath, destPath); err != nil {
			return err
		}
	}

	if err := os.Chmod(filepath.Join(dest, "auto-ssl"), 0o755); err != nil {
		return err
	}

	for _, dir := range []string{"auto-ssl-lib", "auto-ssl-commands"} {
		if err := os.MkdirAll(filepath.Join(dest, dir), 0o755); err != nil {
			return err
		}
	}

	return nil
}

func copyEmbeddedPath(srcPath, destPath string) error {
	info, err := fs.Stat(embeddedBash, srcPath)
	if err != nil {
		return err
	}

	if info.IsDir() {
		if err := os.MkdirAll(destPath, 0o755); err != nil {
			return err
		}
		entries, err := fs.ReadDir(embeddedBash, srcPath)
		if err != nil {
			return err
		}
		for _, entry := range entries {
			childSrc := filepath.ToSlash(filepath.Join(srcPath, entry.Name()))
			childDst := filepath.Join(destPath, entry.Name())
			if err := copyEmbeddedPath(childSrc, childDst); err != nil {
				return err
			}
		}
		return nil
	}

	srcFile, err := embeddedBash.Open(srcPath)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	if err := os.MkdirAll(filepath.Dir(destPath), 0o755); err != nil {
		return err
	}

	dstFile, err := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	if _, err := io.Copy(dstFile, srcFile); err != nil {
		return err
	}

	if filepath.Base(destPath) == "auto-ssl" {
		return os.Chmod(destPath, 0o755)
	}

	return nil
}

func cleanupOldRuntimeDirs(parent, keep string) error {
	entries, err := os.ReadDir(parent)
	if err != nil {
		return err
	}

	var dirs []os.DirEntry
	for _, entry := range entries {
		if entry.IsDir() {
			dirs = append(dirs, entry)
		}
	}

	sort.Slice(dirs, func(i, j int) bool {
		iInfo, iErr := dirs[i].Info()
		jInfo, jErr := dirs[j].Info()
		if iErr != nil || jErr != nil {
			return dirs[i].Name() < dirs[j].Name()
		}
		return iInfo.ModTime().After(jInfo.ModTime())
	})

	kept := 0
	for _, entry := range dirs {
		if entry.Name() == keep {
			continue
		}
		kept++
		if kept > 2 {
			_ = os.RemoveAll(filepath.Join(parent, entry.Name()))
		}
	}

	return nil
}

func embeddedHash() (string, error) {
	h := sha256.New()
	paths := make([]string, 0)
	err := fs.WalkDir(embeddedBash, "assets/bash", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		paths = append(paths, path)
		return nil
	})
	if err != nil {
		return "", err
	}
	sort.Strings(paths)

	for _, path := range paths {
		f, err := embeddedBash.Open(path)
		if err != nil {
			return "", err
		}
		if _, err := io.Copy(h, f); err != nil {
			f.Close()
			return "", err
		}
		f.Close()
	}

	return fmt.Sprintf("%x", h.Sum(nil)), nil
}

func PlatformLabel() string {
	return runtime.GOOS + "/" + runtime.GOARCH
}
