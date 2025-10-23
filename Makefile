.PHONY: help cibw-test test build check clean clean-all setup setup-opensim check-deps

# Platform detection for cross-platform development
UNAME_S := $(shell uname -s 2>/dev/null || echo "Windows")
ifeq ($(UNAME_S),Linux)
	PLATFORM := linux
else ifeq ($(UNAME_S),Darwin)
	PLATFORM := macos
else ifneq ($(findstring MINGW,$(UNAME_S)),)
	PLATFORM := windows
else ifneq ($(findstring CYGWIN,$(UNAME_S)),)
	PLATFORM := windows
else ifeq ($(UNAME_S),Windows)
	PLATFORM := windows
else
	PLATFORM := windows
endif


help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-deps: ## Check if system dependencies are available
	@echo "Checking system dependencies..."
	@git --version >nul 2>&1 || (echo git is required but not installed && exit 1)
	@cmake --version >nul 2>&1 || (echo cmake is required but not installed)	
	@echo "All required system dependencies are available"

setup-opensim: ## Setup OpenSim dependencies if needed
	@echo "Setting up OpenSim dependencies for current platform..."
ifeq ($(PLATFORM),macos)
	@echo "Detected macOS, running macOS setup script..."
	@chmod +x ./scripts/opensim/setup_opensim_macos.sh
	@./scripts/opensim/setup_opensim_macos.sh
else ifeq ($(PLATFORM),linux)
	@echo "Detected Linux, running Linux setup script..."
	@chmod +x ./scripts/opensim/setup_opensim_linux.sh
	@./scripts/opensim/setup_opensim_linux.sh
else ifeq ($(PLATFORM),windows)
	@echo "Detected Windows, running Windows setup script..."
	@powershell -ExecutionPolicy Bypass -File .\scripts\opensim\setup_opensim_windows.ps1
else
	@echo "Unsupported platform: $(PLATFORM)"
	@echo "Please run the appropriate setup script manually:"
	@echo "  - Linux: ./scripts/opensim/setup_opensim_linux.sh"
	@echo "  - macOS: ./scripts/opensim/setup_opensim_macos.sh"
	@echo "  - Windows: powershell -File .\scripts\opensim\setup_opensim_windows.ps1"
	@exit 1
endif

setup: check-deps setup-opensim ## Complete setup: dependencies + OpenSim + Python bindings
	@echo "Setup complete! Use 'make build' to build Python bindings."

build: ## Build the Python bindings
	uv build

check:
	mypy src/pyopensim

clean: ## Clean build artifacts
ifeq ($(PLATFORM),windows)
	@if exist build\cp* rmdir /s /q build\cp*
	@if exist dist rmdir /s /q dist
	@if exist *.egg-info rmdir /s /q *.egg-info
	@for /d /r . %%d in (__pycache__) do @if exist "%%d" rmdir /s /q "%%d"
	@del /s /q *.pyc 2>nul || exit 0
else
	rm -rf build/cp*
	rm -rf dist/
	rm -rf *.egg-info/
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete -type d
endif

clean-all: ## Clean all artifacts
ifeq ($(PLATFORM),windows)
	@if exist build rmdir /s /q build
	@if exist dist rmdir /s /q dist
	@if exist *.egg-info rmdir /s /q *.egg-info
	@for /d /r . %%d in (__pycache__) do @if exist "%%d" rmdir /s /q "%%d"
	@del /s /q *.pyc 2>nul || exit 0
else
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info/
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete -type d
endif

cibw-test:
	@echo "Running CIBW tests..."
	./scripts/cibw_local_wheels.sh

test: ## Run tests
	uv run pytest tests
