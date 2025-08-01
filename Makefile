.PHONY: help test build setup setup-opensim check-deps

# Platform detection for cross-platform development
UNAME_S := $(shell uname -s 2>/dev/null || echo "Windows")
ifeq ($(UNAME_S),Linux)
	PLATFORM := linux
endif
ifeq ($(UNAME_S),Darwin)
	PLATFORM := macos  
endif
ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
	PLATFORM := windows
endif
ifeq ($(findstring CYGWIN,$(UNAME_S)),CYGWIN)
	PLATFORM := windows
endif
ifeq ($(UNAME_S),Windows)
	PLATFORM := windows
endif
ifndef PLATFORM
	PLATFORM := unknown
endif

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-deps: ## Check if system dependencies are available
	@echo "Checking system dependencies..."
	@command -v cmake >/dev/null 2>&1 || { echo "cmake is required but not installed"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "git is required but not installed"; exit 1; }
	@command -v uv >/dev/null 2>&1 || { echo "uv is required but not installed"; exit 1; }
	@echo "All required system dependencies are available"

setup-opensim: ## Setup OpenSim dependencies if needed
	@echo "Setting up OpenSim dependencies for current platform..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		echo "Detected macOS, running macOS setup script..."; \
        chmod +x ./scripts/opensim/setup_opensim_macos.sh; \
		./scripts/opensim/setup_opensim_macos.sh; \
	elif [ "$$(uname)" = "Linux" ]; then \
		echo "Detected Linux, running Linux setup script..."; \
        chmod +x ./scripts/opensim/setup_opensim_linux.sh; \
		./scripts/opensim/setup_opensim_linux.sh; \
	elif [ "$$(uname -s | cut -c1-10)" = "MINGW32_NT" ] || [ "$$(uname -s | cut -c1-10)" = "MINGW64_NT" ] || [ "$$(uname -s | cut -c1-9)" = "CYGWIN_NT" ]; then \
		echo "Detected Windows, running Windows setup script..."; \
		powershell.exe -ExecutionPolicy Bypass -File ./scripts/opensim/setup_opensim_windows.ps1; \
	else \
		echo "Unsupported platform: $$(uname)"; \
		echo "Please run the appropriate setup script manually:"; \
		echo "  - Linux: ./scripts/opensim/setup_opensim_linux.sh"; \
		echo "  - macOS: ./scripts/opensim/setup_opensim_macos.sh"; \
		echo "  - Windows: powershell -ExecutionPolicy Bypass -File ./scripts/opensim/setup_opensim_windows.ps1"; \
		exit 1; \
	fi

setup: check-deps setup-opensim ## Complete setup: dependencies + OpenSim + Python bindings
	@echo "Setup complete! Use 'make build' to build Python bindings."

build: ## Build the Python bindings
	pip install -v .

test: ## Run tests
	python -m pytest tests
