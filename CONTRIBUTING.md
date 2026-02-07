# Contributing to auto-ssl

Thank you for your interest in contributing to auto-ssl! This document provides guidelines and instructions for contributing.

## Code of Conduct

Be respectful, constructive, and professional. We're all here to make internal PKI easier.

## How to Contribute

### Reporting Bugs

**Before submitting a bug report:**
- Check existing issues to avoid duplicates
- Test with the latest version
- Gather relevant information (OS, versions, logs)

**Good bug reports include:**
- Clear, descriptive title
- Steps to reproduce
- Expected vs actual behavior
- Error messages and logs
- Environment details (OS, step-ca version, etc.)

**Example:**
```markdown
**Bug**: CA initialization fails on Ubuntu 22.04

**Steps to reproduce:**
1. Fresh Ubuntu 22.04 install
2. Run: sudo auto-ssl ca init --name "Test CA"
3. Error: "Failed to install step-ca"

**Expected**: CA initializes successfully
**Actual**: Installation fails with permission error

**Environment**:
- OS: Ubuntu 22.04 LTS
- auto-ssl version: 0.1.0
- Error log: [attach log]
```

### Suggesting Features

Feature requests are welcome! Please include:
- Clear use case
- Why existing features don't solve it
- Proposed solution or API
- Willingness to contribute the feature

### Pull Requests

1. **Fork and clone**
   ```bash
   git clone https://github.com/YOUR_USERNAME/auto-ssl.git
   cd auto-ssl
   ```

2. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-123
   ```

3. **Make your changes**
   - Follow the code style (see below)
   - Add tests if applicable
   - Update documentation
   - Test thoroughly

4. **Commit with clear messages**
   ```bash
   git commit -m "Add feature: support for custom SANs in remote enrollment"
   # or
   git commit -m "Fix: password handling in remote enrollment (fixes #123)"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then open a PR on GitHub with:
   - Clear description of changes
   - Reference to related issues
   - Testing performed
   - Screenshots if applicable

## Code Style

### Bash Scripts

- Use `bash` shebang: `#!/usr/bin/env bash`
- Enable strict mode: `set -euo pipefail`
- Quote variables: `"${variable}"` not `$variable`
- Use meaningful function names: `_create_ca_service` not `_ccs`
- Add comments for complex logic
- Check syntax: `bash -n script.sh`

**Example:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Create systemd service for step-ca
_create_ca_service() {
    local password_file="$1"
    
    cat > /etc/systemd/system/step-ca.service << EOF
[Unit]
Description=Smallstep CA
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/step-ca --password-file=${password_file}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}
```

### Go Code (TUI)

- Follow standard Go conventions
- Use `gofmt` for formatting
- Add comments for exported functions
- Write tests for new features
- Run `go vet` and `golangci-lint`

**Example:**
```go
// InitializeCA creates and configures a new Certificate Authority.
// It returns the CA URL and fingerprint on success.
func InitializeCA(name, address string) (*CAInfo, error) {
    if name == "" {
        return nil, errors.New("CA name is required")
    }
    
    // Implementation...
}
```

### Documentation

- Use clear, concise language
- Include examples
- Update all affected docs
- Check for broken links
- Use consistent formatting

## Testing

### Bash Scripts

```bash
# Syntax check
bash -n tui/internal/runtime/assets/bash/auto-ssl
bash -n tui/internal/runtime/assets/bash/commands/*.sh

# Run shellcheck if available
shellcheck tui/internal/runtime/assets/bash/auto-ssl tui/internal/runtime/assets/bash/lib/*.sh tui/internal/runtime/assets/bash/commands/*.sh
```

### Go Tests

```bash
cd tui
go test ./...
go test -race ./...
go test -cover ./...
```

### Manual Testing

Test your changes on:
- Fresh VM/container
- Different OS (RHEL, Ubuntu)
- Different scenarios (new install, upgrade, etc.)

## Development Setup

### Prerequisites

- Bash 4+
- Go 1.21+ (for TUI)
- make
- git

### Build from source

```bash
# Clone
git clone https://github.com/Brightblade42/auto-ssl.git
cd auto-ssl

# Build TUI
make build-tui

# Install locally (requires sudo)
sudo make install
```

### Development workflow

```bash
# Work on bash scripts
vim tui/internal/runtime/assets/bash/commands/server.sh
bash -n tui/internal/runtime/assets/bash/commands/server.sh  # syntax check
sudo auto-ssl server status      # test

# Work on TUI
cd tui
vim internal/app/app.go
go run ./cmd/auto-ssl  # test
go test ./...          # run tests
```

## Documentation Changes

Documentation is in `docs/`:
- `concepts/` - PKI concepts and theory
- `guides/` - Step-by-step guides
- `reference/` - Reference material

When adding features:
1. Update relevant guide
2. Update README if it affects main workflow
3. Add example to appropriate doc
4. Update CLI help text

## Commit Guidelines

### Commit Message Format

```
<type>: <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Example:**
```
feat: add support for IPv6 addresses in server enrollment

- Update IP validation to accept IPv6
- Add IPv6 tests
- Update documentation

Closes #234
```

## Release Process

(For maintainers)

1. Update `CHANGELOG.md`
2. Update version in `tui/internal/runtime/assets/bash/lib/common.sh`
3. Tag release: `git tag v0.2.0`
4. Build binaries: `make dist`
5. Create GitHub release
6. Update documentation

## Questions?

- Open a [discussion](https://github.com/Brightblade42/auto-ssl/discussions)
- Ask in issues
- Check existing documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
