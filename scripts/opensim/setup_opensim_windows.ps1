# Setup script for OpenSim on Windows
# This script orchestrates the OpenSim build process for local development

param(
    [switch]$DepsOnly,
    [switch]$Force,
    [string]$BuildType = "Release",
    [int]$Jobs = 4
)

$ErrorActionPreference = "Stop"

# Get script directory and project root
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$COMMON_DIR = Join-Path $SCRIPT_DIR "common"
$OPENSIM_ROOT = Get-Location
$WORKSPACE_DIR = Join-Path $OPENSIM_ROOT "build\opensim-workspace"

Write-Host "=== OpenSim Windows Setup ===" -ForegroundColor Cyan
Write-Host "Build type: $BuildType"
Write-Host "Jobs: $Jobs"
Write-Host "Workspace: $WORKSPACE_DIR"

# Create workspace
New-Item -ItemType Directory -Force -Path $WORKSPACE_DIR | Out-Null

# Step 1: Verify Visual Studio installation
Write-Host ""
Write-Host "=== Step 1: Checking Visual Studio installation ===" -ForegroundColor Cyan

# Try to find Visual Studio 2022
$programFilesX86 = ${env:ProgramFiles(x86)}
$vsWhere = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"

if (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -property installationPath
    if ($vsPath) {
        Write-Host "Found Visual Studio 2022 at: $vsPath" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Visual Studio 2022 not found" -ForegroundColor Red
        Write-Host "Please install Visual Studio 2022" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "WARNING: Could not verify Visual Studio installation" -ForegroundColor Yellow
}

# Step 2: Install SWIG via Chocolatey
Write-Host ""
Write-Host "=== Step 2: Installing SWIG ===" -ForegroundColor Cyan

# Check if Chocolatey is installed
$chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
if (-not $chocoCmd) {
    Write-Host "ERROR: Chocolatey is not installed" -ForegroundColor Red
    Write-Host "Install from: https://chocolatey.org/install" -ForegroundColor Yellow
    exit 1
}

# Always install SWIG 4.1.1, forcing downgrade/reinstall if needed
# This matches the CI approach and ensures we get the exact version
# The --force flag is critical: without it, chocolatey won't downgrade from pre-installed versions
Write-Host "Installing SWIG 4.1.1 via Chocolatey..."
choco install swig --version 4.1.1 --yes --limit-output --allow-downgrade --force
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install SWIG 4.1.1"
}

# Refresh environment to get swig in PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Verify installation
Write-Host "`nVerifying SWIG installation:" -ForegroundColor Cyan
$swigCmd = Get-Command swig -ErrorAction SilentlyContinue
if (-not $swigCmd) {
    throw "SWIG not found in PATH after installation"
}

Write-Host "SWIG installed at: $($swigCmd.Source)" -ForegroundColor Green
& swig -version

$SWIG_EXE = $swigCmd.Source
$SWIG_DIR = Split-Path -Parent $SWIG_EXE
$SWIG_DIR = Join-Path (Split-Path -Parent $SWIG_DIR) "share\swig"

Write-Host "SWIG executable: $SWIG_EXE" -ForegroundColor Green
Write-Host "SWIG directory: $SWIG_DIR" -ForegroundColor Green

# Exit early if only installing dependencies
if ($DepsOnly) {
    Write-Host ""
    Write-Host "Dependencies check complete." -ForegroundColor Green
    exit 0
}

# Step 3: Build OpenSim dependencies
Write-Host ""
Write-Host "=== Step 3: Building OpenSim dependencies ===" -ForegroundColor Cyan

$DEPS_SOURCE = Join-Path $OPENSIM_ROOT "src\opensim-core\dependencies"
$DEPS_BUILD_DIR = Join-Path $WORKSPACE_DIR "dependencies-build"
$DEPS_INSTALL_DIR = Join-Path $WORKSPACE_DIR "dependencies-install"

# Check if dependencies are already built
$DEPS_COMPLETE = Join-Path $DEPS_INSTALL_DIR ".build_complete"
if ((Test-Path $DEPS_COMPLETE) -and -not $Force) {
    Write-Host "Dependencies already built at $DEPS_INSTALL_DIR" -ForegroundColor Green
    Write-Host "Use -Force to rebuild" -ForegroundColor Yellow
} else {
    if ($Force) {
        Write-Host "Force rebuild requested - removing existing directories" -ForegroundColor Yellow
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $DEPS_BUILD_DIR, $DEPS_INSTALL_DIR
    }

    Write-Host "Building dependencies from scratch..."

    # Get CMake flags from preset
    $PRESETS_FILE = Join-Path $OPENSIM_ROOT "CMakePresets.json"
    $PARSE_SCRIPT = Join-Path $COMMON_DIR "parse_preset.py"

    Write-Host "Extracting CMake flags from preset: opensim-dependencies-windows"
    $CMAKE_FLAGS_STR = & python $PARSE_SCRIPT $PRESETS_FILE "opensim-dependencies-windows"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to parse preset"
    }

    $CMAKE_FLAGS = $CMAKE_FLAGS_STR -split ' '
    Write-Host "CMake flags: $CMAKE_FLAGS_STR"

    # Create build directory
    New-Item -ItemType Directory -Force -Path $DEPS_BUILD_DIR | Out-Null
    Set-Location $DEPS_BUILD_DIR

    # Configure
    Write-Host "Configuring dependencies..."

    # Build cmake arguments using preset (which includes all compiler flags)
    $configArgs = @(
        $DEPS_SOURCE,
        "--preset", "opensim-dependencies-windows",
        "-DCMAKE_INSTALL_PREFIX=$DEPS_INSTALL_DIR"
    )

    Write-Host "Running CMake configuration..."
    # Use preset directly - it contains all necessary flags including /utf-8
    & cmake @configArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed"
    }

    # Build
    Write-Host "Building dependencies (this may take 15-30 minutes)..."
    & cmake --build . --config $BuildType -j $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed"
    }

    # Mark as complete
    New-Item -ItemType File -Path $DEPS_COMPLETE -Force | Out-Null
    Write-Host "Dependencies build complete" -ForegroundColor Green
}

# Step 4: Build OpenSim core
Write-Host ""
Write-Host "=== Step 4: Building OpenSim core ===" -ForegroundColor Cyan

$OPENSIM_SOURCE = Join-Path $OPENSIM_ROOT "src\opensim-core"
$OPENSIM_BUILD_DIR = Join-Path $WORKSPACE_DIR "opensim-build"
$OPENSIM_INSTALL_DIR = Join-Path $WORKSPACE_DIR "opensim-install"

# Check if OpenSim is already built
$OPENSIM_COMPLETE = Join-Path $OPENSIM_INSTALL_DIR ".build_complete"
if ((Test-Path $OPENSIM_COMPLETE) -and -not $Force) {
    Write-Host "OpenSim already built at $OPENSIM_INSTALL_DIR" -ForegroundColor Green
    Write-Host "Use -Force to rebuild" -ForegroundColor Yellow
} else {
    if ($Force) {
        Write-Host "Force rebuild requested - removing existing directories" -ForegroundColor Yellow
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $OPENSIM_BUILD_DIR, $OPENSIM_INSTALL_DIR
    }

    Write-Host "Building OpenSim from scratch..."

    # Get CMake flags from preset
    $PRESETS_FILE = Join-Path $OPENSIM_ROOT "CMakePresets.json"
    $PARSE_SCRIPT = Join-Path $COMMON_DIR "parse_preset.py"

    Write-Host "Extracting CMake flags from preset: opensim-core-windows"
    $CMAKE_FLAGS_STR = & python $PARSE_SCRIPT $PRESETS_FILE "opensim-core-windows"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to parse preset"
    }

    $CMAKE_FLAGS = $CMAKE_FLAGS_STR -split ' '
    Write-Host "CMake flags: $CMAKE_FLAGS_STR"

    # Copy CMakePresets.json to OpenSim source directory
    Write-Host "Copying CMakePresets.json to OpenSim source directory..."
    Copy-Item $PRESETS_FILE $OPENSIM_SOURCE -Force

    # Apply patch to skip Examples directory (avoids find_package(OpenSim) issue)
    $PATCH_FILE = Join-Path $OPENSIM_ROOT "patches\skip-examples.patch"
    $OPENSIM_CMAKE = Join-Path $OPENSIM_SOURCE "OpenSim\CMakeLists.txt"
    if (Test-Path $PATCH_FILE) {
        Write-Host "Applying patch to skip Examples directory..."
        # Check if already patched
        $content = Get-Content $OPENSIM_CMAKE -Raw
        if ($content -notmatch 'if\(BUILD_API_EXAMPLES\)[\s\S]*add_subdirectory\(Examples\)') {
            # Simple text replacement instead of git apply (more reliable on Windows)
            $content = $content -replace 'add_subdirectory\(Examples\)', "if(BUILD_API_EXAMPLES)`n    add_subdirectory(Examples)`nendif()"
            Set-Content -Path $OPENSIM_CMAKE -Value $content
            Write-Host "Patch applied successfully" -ForegroundColor Green
        } else {
            Write-Host "Patch already applied, skipping" -ForegroundColor Yellow
        }
    }

    # Create build directory
    New-Item -ItemType Directory -Force -Path $OPENSIM_BUILD_DIR | Out-Null
    Set-Location $OPENSIM_BUILD_DIR

    # Configure
    Write-Host "Configuring OpenSim..."

    # Build cmake arguments using preset (which includes all compiler flags)
    $configArgs = @(
        $OPENSIM_SOURCE,
        "--preset", "opensim-core-windows",
        "-DCMAKE_INSTALL_PREFIX=$OPENSIM_INSTALL_DIR",
        "-DOPENSIM_DEPENDENCIES_DIR=$DEPS_INSTALL_DIR",
        "-DCMAKE_PREFIX_PATH=$DEPS_INSTALL_DIR",
        "-DSWIG_DIR=$SWIG_DIR",
        "-DSWIG_EXECUTABLE=$SWIG_EXE"
    )

    Write-Host "Running CMake configuration..."
    # Use preset directly - it contains all necessary flags including /utf-8 and /bigobj
    & cmake @configArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed"
    }

    # Build
    Write-Host "Building OpenSim (this may take 20-40 minutes)..."
    & cmake --build . --config $BuildType -j $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed"
    }

    # Install
    Write-Host "Installing OpenSim..."
    & cmake --install . --config $BuildType
    if ($LASTEXITCODE -ne 0) {
        throw "Installation failed"
    }

    # Mark as complete
    New-Item -ItemType File -Path $OPENSIM_COMPLETE -Force | Out-Null
    Write-Host "OpenSim build complete" -ForegroundColor Green
}

Write-Host ""
Write-Host "OpenSim setup complete!" -ForegroundColor Green
Write-Host "Libraries installed in: $OPENSIM_INSTALL_DIR" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "Run 'python -m build' to build the Python bindings" -ForegroundColor White
