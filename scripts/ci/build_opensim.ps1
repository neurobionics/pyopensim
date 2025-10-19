# CI-specific OpenSim build orchestrator for Windows
# This script wraps the common build logic with CI-specific caching and path handling
#
# Usage:
#   build_opensim.ps1 -CacheDir <path> [-Force] [-Jobs <n>]
#
# Environment variables expected from CI:
#   OPENSIM_SHA: Git SHA of opensim-core submodule (for cache validation)

param(
    [Parameter(Mandatory=$true)]
    [string]$CacheDir,

    [switch]$Force,

    [int]$Jobs = 4
)

$ErrorActionPreference = "Stop"

# Get script directory
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$COMMON_DIR = Join-Path $SCRIPT_DIR "..\opensim\common"

# Set up paths
$OPENSIM_INSTALL = Join-Path $CacheDir "opensim-install"
$DEPS_INSTALL = Join-Path $CacheDir "dependencies-install"

Write-Host "=== CI OpenSim Build (Windows) ===" -ForegroundColor Cyan
Write-Host "Cache dir: $CacheDir"
Write-Host "Jobs: $Jobs"
Write-Host "Preset (deps): opensim-dependencies-windows"
Write-Host "Preset (core): opensim-core-windows"

# Get project root (assumes this script is in scripts/ci/)
$PROJECT_ROOT = Join-Path $SCRIPT_DIR "..\.."
$PROJECT_ROOT = [System.IO.Path]::GetFullPath($PROJECT_ROOT)

# Check if we have a cached build
$BUILD_COMPLETE = Join-Path $OPENSIM_INSTALL ".build_complete"
if ((Test-Path $BUILD_COMPLETE) -and -not $Force) {
    Write-Host "✓ Using cached OpenSim build from $OPENSIM_INSTALL" -ForegroundColor Green

    # Verify cache is valid by checking for critical files
    $SDK_LIB = Join-Path $OPENSIM_INSTALL "sdk\lib"
    if (Test-Path $SDK_LIB) {
        Write-Host "✓ Cache validation passed" -ForegroundColor Green
        Get-ChildItem $SDK_LIB | Select-Object -First 10 | Format-Table Name, Length
    } else {
        Write-Host "Warning: Cache appears corrupted, rebuilding..." -ForegroundColor Yellow
        $Force = $true
    }
}

if ($Force -or -not (Test-Path $BUILD_COMPLETE)) {
    Write-Host "Building OpenSim from scratch..." -ForegroundColor Cyan

    # Create cache directory
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    Set-Location $CacheDir

    # Step 1: Install SWIG via Chocolatey
    Write-Host "`n=== Step 1: Installing SWIG ===" -ForegroundColor Cyan
    Write-Host "Installing SWIG 4.1.1 via Chocolatey..."

    # Check if SWIG is already installed
    $swigInstalled = Get-Command swig -ErrorAction SilentlyContinue
    if ($swigInstalled) {
        Write-Host "SWIG already installed at: $($swigInstalled.Source)" -ForegroundColor Green
        & swig -version
    } else {
        choco install swig --version 4.1.1 --yes --limit-output --allow-downgrade
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install SWIG"
        }
        # Refresh environment to get swig in PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }

    $SWIG_EXE = (Get-Command swig).Source
    $SWIG_DIR = Split-Path -Parent $SWIG_EXE
    $SWIG_DIR = Join-Path (Split-Path -Parent $SWIG_DIR) "share\swig"

    Write-Host "SWIG executable: $SWIG_EXE" -ForegroundColor Green
    Write-Host "SWIG directory: $SWIG_DIR" -ForegroundColor Green

    # Step 2: Build dependencies using CMake presets
    Write-Host "`n=== Step 2: Building OpenSim dependencies ===" -ForegroundColor Cyan

    $DEPS_SOURCE = Join-Path $PROJECT_ROOT "src\opensim-core\dependencies"
    $DEPS_BUILD_DIR = Join-Path $CacheDir "dependencies-build"

    Write-Host "Source: $DEPS_SOURCE"
    Write-Host "Build: $DEPS_BUILD_DIR"
    Write-Host "Install: $DEPS_INSTALL"

    # Get CMake flags from preset using Python parser
    $PRESETS_FILE = Join-Path $PROJECT_ROOT "CMakePresets.json"
    $PARSE_SCRIPT = Join-Path $COMMON_DIR "parse_preset.py"

    Write-Host "Extracting CMake flags from preset: opensim-dependencies-windows"
    $CMAKE_FLAGS_STR = & python $PARSE_SCRIPT $PRESETS_FILE "opensim-dependencies-windows"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to parse preset 'opensim-dependencies-windows'"
    }

    # Convert space-separated flags to array and filter out C/CXX flags
    $CMAKE_FLAGS = $CMAKE_FLAGS_STR -split ' '

    # Extract non-compiler flags (compiler flags will be set via cmake -E env)
    $otherFlags = @()
    foreach ($flag in $CMAKE_FLAGS) {
        if (-not ($flag -match "CMAKE_C(XX)?_FLAGS")) {
            $otherFlags += $flag
        }
    }

    Write-Host "CMake flags: $CMAKE_FLAGS_STR"

    # Create build directory
    New-Item -ItemType Directory -Force -Path $DEPS_BUILD_DIR | Out-Null
    Set-Location $DEPS_BUILD_DIR

    # Configure dependencies (matching OpenSim's official CI approach)
    Write-Host "Configuring dependencies..."
    $configArgs = @(
        $DEPS_SOURCE,
        '-G"Visual Studio 17 2022"',
        "-A", "x64",
        "-DCMAKE_INSTALL_PREFIX=$DEPS_INSTALL"
    ) + $otherFlags

    # Use cmake -E env to set compiler flags like OpenSim's official CI
    & cmake -E env CXXFLAGS="/MD /W0" CFLAGS="/MD /W0" cmake @configArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed for dependencies"
    }

    # Build dependencies
    Write-Host "Building dependencies (this may take 15-30 minutes)..."
    & cmake --build . --config Release -j $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for dependencies"
    }

    # Step 3: Build OpenSim core using CMake presets
    Write-Host "`n=== Step 3: Building OpenSim core ===" -ForegroundColor Cyan

    $OPENSIM_SOURCE = Join-Path $PROJECT_ROOT "src\opensim-core"
    $OPENSIM_BUILD_DIR = Join-Path $CacheDir "opensim-build"

    Write-Host "Source: $OPENSIM_SOURCE"
    Write-Host "Build: $OPENSIM_BUILD_DIR"
    Write-Host "Install: $OPENSIM_INSTALL"

    # Copy CMakePresets.json to OpenSim source directory
    Write-Host "Copying CMakePresets.json to OpenSim source directory..."
    Copy-Item $PRESETS_FILE $OPENSIM_SOURCE -Force

    # Create build directory
    New-Item -ItemType Directory -Force -Path $OPENSIM_BUILD_DIR | Out-Null
    Set-Location $OPENSIM_BUILD_DIR

    # Configure OpenSim (matching OpenSim's official CI approach)
    Write-Host "Configuring OpenSim..."
    $configArgs = @(
        $OPENSIM_SOURCE,
        "--preset", "opensim-core-windows",
        "-DCMAKE_INSTALL_PREFIX=$OPENSIM_INSTALL",
        "-DOPENSIM_DEPENDENCIES_DIR=$DEPS_INSTALL",
        "-DCMAKE_PREFIX_PATH=$DEPS_INSTALL",
        "-DSWIG_DIR=$SWIG_DIR",
        "-DSWIG_EXECUTABLE=$SWIG_EXE"
    )

    # Use cmake -E env to set compiler flags like OpenSim's official CI
    & cmake -E env CXXFLAGS="/MD /W0" CFLAGS="/MD /W0" cmake @configArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed for OpenSim"
    }

    # Build OpenSim
    Write-Host "Building OpenSim core (this may take 20-40 minutes)..."
    & cmake --build . --config Release -j $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for OpenSim"
    }

    # Install OpenSim
    Write-Host "Installing OpenSim..."
    & cmake --install . --config Release
    if ($LASTEXITCODE -ne 0) {
        throw "Installation failed for OpenSim"
    }

    # Mark as complete
    New-Item -ItemType File -Path $BUILD_COMPLETE -Force | Out-Null

    Write-Host "`n✓ OpenSim build complete" -ForegroundColor Green
}

# Set environment variables for subsequent build steps
Write-Host "`n=== Setting up build environment ===" -ForegroundColor Cyan
$env:OPENSIM_INSTALL_DIR = $OPENSIM_INSTALL

# Verify SWIG is available
$swigCmd = Get-Command swig -ErrorAction SilentlyContinue
if ($swigCmd) {
    Write-Host "  SWIG: $($swigCmd.Source)" -ForegroundColor Green
    & swig -version | Select-Object -First 3
} else {
    Write-Host "  WARNING: SWIG not in PATH" -ForegroundColor Yellow
}

Write-Host "  OPENSIM_INSTALL_DIR: $env:OPENSIM_INSTALL_DIR" -ForegroundColor Green

Write-Host "`n✓ CI build environment ready" -ForegroundColor Green
Write-Host "  OpenSim installed at: $OPENSIM_INSTALL" -ForegroundColor Green
