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

# Convert CacheDir to absolute path (in case it's relative)
$CacheDir = [System.IO.Path]::GetFullPath($CacheDir)

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
if ((Test-Path $BUILD_COMPLETE) -and (-not $Force)) {
    Write-Host "[OK] Using cached OpenSim build from $OPENSIM_INSTALL" -ForegroundColor Green

    # Verify cache is valid by checking for critical files
    $SDK_LIB = Join-Path $OPENSIM_INSTALL "sdk\lib"
    if (Test-Path $SDK_LIB) {
        Write-Host "[OK] Cache validation passed" -ForegroundColor Green
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

    # Always install SWIG 4.1.1, forcing downgrade/reinstall if needed
    # This matches the official OpenSim CI approach and ensures we get the exact version
    # The --force flag is critical: without it, chocolatey won't downgrade from 4.3.1 (pre-installed on GitHub Actions)
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

    Write-Host "CMake flags: $CMAKE_FLAGS_STR"

    # Create build directory
    New-Item -ItemType Directory -Force -Path $DEPS_BUILD_DIR | Out-Null
    Set-Location $DEPS_BUILD_DIR

    # Configure dependencies using preset (which includes all compiler flags)
    Write-Host "Configuring dependencies..."
    $configArgs = @(
        $DEPS_SOURCE,
        "--preset", "opensim-dependencies-windows",
        "-DCMAKE_INSTALL_PREFIX=$DEPS_INSTALL"
    )

    # Use preset directly - it contains all necessary flags including /utf-8
    & cmake @configArgs
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

    # Apply patch to skip Examples directory (avoids find_package(OpenSim) issue)
    $PATCH_FILE = Join-Path $PROJECT_ROOT "patches\skip-examples.patch"
    $OPENSIM_CMAKE = Join-Path $OPENSIM_SOURCE "OpenSim\CMakeLists.txt"
    if (Test-Path $PATCH_FILE) {
        Write-Host "Applying patch to skip Examples directory..."
        # Check if already patched
        $content = Get-Content $OPENSIM_CMAKE -Raw
        if ($content -notmatch 'if\(BUILD_API_EXAMPLES\)[\s\S]*add_subdirectory\(Examples\)') {
            # Simple text replacement instead of git apply (more reliable on Windows)
            $content = $content -replace 'add_subdirectory\(Examples\)', "if(BUILD_API_EXAMPLES)`n    add_subdirectory(Examples)`nendif()"
            Set-Content -Path $OPENSIM_CMAKE -Value $content
            Write-Host "Patch applied successfully"
        } else {
            Write-Host "Patch already applied, skipping"
        }
    }

    # Create build directory
    New-Item -ItemType Directory -Force -Path $OPENSIM_BUILD_DIR | Out-Null
    Set-Location $OPENSIM_BUILD_DIR

    # Configure OpenSim using preset (which includes all compiler flags)
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

    # Use preset directly - it contains all necessary flags including /utf-8 and /bigobj
    & cmake @configArgs
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

    Write-Host "`n[OK] OpenSim build complete" -ForegroundColor Green
}  # End of: if ($Force -or -not (Test-Path $BUILD_COMPLETE))

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

Write-Host "`n[OK] CI build environment ready" -ForegroundColor Green
Write-Host "  OpenSim installed at: $OPENSIM_INSTALL" -ForegroundColor Green
