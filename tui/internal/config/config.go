package config

import (
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	DefaultConfigDir   = "/etc/auto-ssl"
	DefaultConfigFile  = "config.yaml"
	DefaultCertDir     = "/etc/ssl/auto-ssl"
	DefaultStepCAPath  = "/opt/step-ca"
)

// Config represents the auto-ssl configuration
type Config struct {
	CA       CAConfig       `yaml:"ca"`
	Defaults DefaultsConfig `yaml:"defaults"`
	Backup   BackupConfig   `yaml:"backup"`
	Server   ServerConfig   `yaml:"server"`
	
	// Runtime fields (not saved)
	path string `yaml:"-"`
}

// CAConfig holds CA-related configuration
type CAConfig struct {
	URL         string `yaml:"url"`
	Fingerprint string `yaml:"fingerprint"`
	Name        string `yaml:"name"`
	StepPath    string `yaml:"steppath"`
}

// DefaultsConfig holds default values
type DefaultsConfig struct {
	CertDuration    string `yaml:"cert_duration"`
	MaxCertDuration string `yaml:"max_cert_duration"`
}

// BackupConfig holds backup configuration
type BackupConfig struct {
	Enabled       bool                `yaml:"enabled"`
	Schedule      string              `yaml:"schedule"`
	Retention     int                 `yaml:"retention"`
	Passphrase    string              `yaml:"passphrase_file,omitempty"`
	Destinations  []BackupDestination `yaml:"destinations"`
}

// BackupDestination represents a backup target
type BackupDestination struct {
	Type     string `yaml:"type"`              // local, rsync, s3
	Path     string `yaml:"path,omitempty"`    // for local
	Target   string `yaml:"target,omitempty"`  // for rsync
	Bucket   string `yaml:"bucket,omitempty"`  // for s3
	Endpoint string `yaml:"endpoint,omitempty"` // for s3 (Wasabi)
	Prefix   string `yaml:"prefix,omitempty"`  // for s3
}

// ServerConfig holds server-specific configuration
type ServerConfig struct {
	CertPath string `yaml:"cert_path"`
	KeyPath  string `yaml:"key_path"`
	SANs     string `yaml:"sans"`
}

// Server represents an enrolled server in the inventory
type Server struct {
	Host            string    `yaml:"host"`
	Name            string    `yaml:"name"`
	User            string    `yaml:"user"`
	Enrolled        bool      `yaml:"enrolled"`
	Suspended       bool      `yaml:"suspended"`
	SuspendedAt     time.Time `yaml:"suspended_at,omitempty"`
	SuspendedReason string    `yaml:"suspended_reason,omitempty"`
	EnrolledAt      time.Time `yaml:"enrolled_at,omitempty"`
	LastSeen        time.Time `yaml:"last_seen,omitempty"`
	CertExpires     time.Time `yaml:"cert_expires,omitempty"`
}

// Inventory holds the list of enrolled servers
type Inventory struct {
	Servers []Server `yaml:"servers"`
	path    string   `yaml:"-"`
}

// Load reads the configuration file or returns defaults
func Load() *Config {
	cfg := &Config{
		Defaults: DefaultsConfig{
			CertDuration:    "168h",  // 7 days
			MaxCertDuration: "720h",  // 30 days
		},
		CA: CAConfig{
			StepPath: DefaultStepCAPath,
		},
		Server: ServerConfig{
			CertPath: filepath.Join(DefaultCertDir, "server.crt"),
			KeyPath:  filepath.Join(DefaultCertDir, "server.key"),
		},
		path: filepath.Join(DefaultConfigDir, DefaultConfigFile),
	}
	
	// Try to load existing config
	data, err := os.ReadFile(cfg.path)
	if err != nil {
		return cfg
	}
	
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return cfg
	}
	
	return cfg
}

// Save writes the configuration to disk
func (c *Config) Save() error {
	// Ensure directory exists
	dir := filepath.Dir(c.path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	
	data, err := yaml.Marshal(c)
	if err != nil {
		return err
	}
	
	return os.WriteFile(c.path, data, 0600)
}

// LoadInventory reads the server inventory
func LoadInventory() *Inventory {
	inv := &Inventory{
		path: filepath.Join(DefaultConfigDir, "servers.yaml"),
	}
	
	data, err := os.ReadFile(inv.path)
	if err != nil {
		return inv
	}
	
	yaml.Unmarshal(data, inv)
	return inv
}

// Save writes the inventory to disk
func (i *Inventory) Save() error {
	dir := filepath.Dir(i.path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	
	data, err := yaml.Marshal(i)
	if err != nil {
		return err
	}
	
	return os.WriteFile(i.path, data, 0600)
}

// AddServer adds or updates a server in the inventory
func (i *Inventory) AddServer(server Server) {
	// Check if already exists
	for idx, s := range i.Servers {
		if s.Host == server.Host {
			i.Servers[idx] = server
			return
		}
	}
	i.Servers = append(i.Servers, server)
}

// GetServer returns a server by host
func (i *Inventory) GetServer(host string) *Server {
	for idx := range i.Servers {
		if i.Servers[idx].Host == host {
			return &i.Servers[idx]
		}
	}
	return nil
}

// RemoveServer removes a server from the inventory
func (i *Inventory) RemoveServer(host string) {
	for idx, s := range i.Servers {
		if s.Host == host {
			i.Servers = append(i.Servers[:idx], i.Servers[idx+1:]...)
			return
		}
	}
}
