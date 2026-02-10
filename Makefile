# auto-ssl Makefile
# Build and install targets for the Go bootstrap companion

.PHONY: all build build-helper build-tui install install-helper install-tui install-wrapper clean test help

# Variables
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
GO_LDFLAGS := -ldflags "-X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)"

INSTALL_DIR ?= /usr/local/bin
CONFIG_DIR ?= /etc/auto-ssl

# Default target
all: build

#--------------------------------------------------
# Build targets
#--------------------------------------------------

build: build-helper ## Build auto-ssl companion binary
	@echo "Build complete"

build-helper: ## Build the Go bootstrap/helper companion
	@echo "Building auto-ssl companion..."
	cd tui && go build $(GO_LDFLAGS) -o ../bin/auto-ssl-tui ./cmd/auto-ssl
	@echo "Built: bin/auto-ssl-tui"

build-tui: build-helper ## Backward-compatible alias

#--------------------------------------------------
# Install targets
#--------------------------------------------------

install: install-helper install-wrapper ## Install auto-ssl-tui and auto-ssl wrapper
	@echo "Installation complete"

install-helper: ## Install Go bootstrap/helper companion
	@echo "Installing companion helper..."
	install -m 755 bin/auto-ssl-tui $(INSTALL_DIR)/auto-ssl-tui
	@echo "Companion installed to $(INSTALL_DIR)/auto-ssl-tui"

install-tui: install-helper ## Backward-compatible alias

install-wrapper: ## Install auto-ssl compatibility wrapper
	@echo "Installing auto-ssl wrapper..."
	install -d $(INSTALL_DIR)
	install -m 755 scripts/auto-ssl-wrapper.sh $(INSTALL_DIR)/auto-ssl
	@echo "Wrapper installed to $(INSTALL_DIR)/auto-ssl"

install-completions: ## Install shell completions
	@echo "Installing shell completions..."
	install -d /etc/bash_completion.d
	install -m 644 tui/internal/runtime/assets/bash/completions/auto-ssl.bash /etc/bash_completion.d/auto-ssl
	@if [ -d /usr/share/zsh/site-functions ]; then \
		install -m 644 tui/internal/runtime/assets/bash/completions/auto-ssl.zsh /usr/share/zsh/site-functions/_auto-ssl; \
	fi
	@echo "Completions installed"

#--------------------------------------------------
# Development targets
#--------------------------------------------------

dev: ## Run helper CLI in development mode
	cd tui && go run ./cmd/auto-ssl --help

test: ## Run all tests
	cd tui && go test -v ./...

test-coverage: ## Run tests with coverage
	cd tui && go test -coverprofile=coverage.out ./...
	cd tui && go tool cover -html=coverage.out

lint: ## Run linters
	cd tui && golangci-lint run

fmt: ## Format Go code
	cd tui && go fmt ./...

#--------------------------------------------------
# Clean targets
#--------------------------------------------------

clean: ## Clean build artifacts
	rm -rf bin/
	rm -rf dist/
	rm -f tui/coverage.out
	cd tui && go clean

#--------------------------------------------------
# Release targets
#--------------------------------------------------

dist: ## Build release binaries for all platforms
	@echo "Building release binaries..."
	mkdir -p dist
	# Linux AMD64
	cd tui && GOOS=linux GOARCH=amd64 go build $(GO_LDFLAGS) -o ../dist/auto-ssl-tui-linux-amd64 ./cmd/auto-ssl
	# Linux ARM64
	cd tui && GOOS=linux GOARCH=arm64 go build $(GO_LDFLAGS) -o ../dist/auto-ssl-tui-linux-arm64 ./cmd/auto-ssl
	# macOS AMD64
	cd tui && GOOS=darwin GOARCH=amd64 go build $(GO_LDFLAGS) -o ../dist/auto-ssl-tui-darwin-amd64 ./cmd/auto-ssl
	# macOS ARM64
	cd tui && GOOS=darwin GOARCH=arm64 go build $(GO_LDFLAGS) -o ../dist/auto-ssl-tui-darwin-arm64 ./cmd/auto-ssl
	@echo "Release binaries built in dist/"

#--------------------------------------------------
# Help
#--------------------------------------------------

help: ## Show this help
	@echo "auto-ssl - Internal PKI made easy"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
