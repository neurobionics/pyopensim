# OpenSim setup script for Windows (local development)
# This script orchestrates the Windows build process using CMake presets
#
# Usage:
#   setup_opensim_windows.ps1 [-Force] [-DepsOnly] [-Jobs <n>] [-Preset <name>]
#
# Examples:
#   .\setup_opensim_windows.ps1                    # Standard build
#   .\setup_opensim_windows.ps1 -Force             # Force rebuild from scratch
#   .\setup_opensim_windows.ps1 -Jobs 8            # Use 8 parallel jobs
#   .\setup_opensim_windows.ps1 -DepsOnly          # Install dependencies only

param(
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$DepsOnly,

    [Parameter(Mandatory=$false)]
    [int]$Jobs = $env:NUMBER_OF_PROCESSORS,

    [Parameter(Mandatory=$false)]
    [string]$Preset = "opensim-core-windows",

    [Parameter(Mandatory=$false)]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host @"
OpenSim Windows Setup Script

Usage: setup_opensim_windows.ps1 [options]

Options:
  -Force          Force rebuild (ignore cache)
  -DepsOnly       Install system dependencies only (skip OpenSim build)
  -Jobs <n>       Number of parallel jobs (default: $env:NUMBER_OF_PROCESSORS)
  -Preset <name>  CMake preset to use (default: opensim-core-windows)
  -Help           Show this help message

Examples:
  .\setup_opensim_windows.ps1
  .\setup_opensim_windows.ps1 -Force -Jobs 8
  .\setup_opensim_windows.ps1 -DepsOnly

Note: Requires Visual Studio 2022 with C++ workload installed.
"@
    exit 0
}

if ($Help) {
    Show-Help
}

# Get script and project directories
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$CommonDir = Join-Path $ScriptDir "common"

Write-Host "=== OpenSim Windows Setup ===" -ForegroundColor Cyan
Write-Host "Project root: $ProjectRoot"
Write-Host "Jobs: $Jobs"
Write-Host "Preset: $Preset"
Write-Host "Force rebuild: $Force"

# Set up paths
$WorkspaceDir = Join-Path $ProjectRoot "build\opensim-workspace"
$OpensimInstall = Join-Path $WorkspaceDir "opensim-install"
$DepsInstall = Join-Path $WorkspaceDir "dependencies-install"
$SwigInstall = Join-Path $WorkspaceDir "swig-install"
$DepsSource = Join-Path $ProjectRoot "src\opensim-core\dependencies"
$OpensimSource = Join-Path $ProjectRoot "src\opensim-core"

# Determine dependency preset based on core preset
$DepsPreset = "opensim-dependencies-windows"

# Create workspace directory
New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null

# Step 1: Install system dependencies (if requested or if first time)
if ($DepsOnly -or (-not (Test-Path (Join-Path $SwigInstall "bin\swig.exe")))) {
    Write-Host ""
    Write-Host "Step 1: Installing system dependencies..." -ForegroundColor Cyan

    Write-Host "NOTE: This script assumes Visual Studio 2022 is already installed." -ForegroundColor Yellow
    Write-Host "      If not, please install VS 2022 Community with C++ workload first." -ForegroundColor Yellow
    Write-Host ""

    # Check for Visual Studio
    $VSPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $VSPath)) {
        $VSPath = "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
    }
    if (-not (Test-Path $VSPath)) {
        $VSPath = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    }

    if (-not (Test-Path $VSPath)) {
        Write-Host "ERROR: Visual Studio 2022 not found!" -ForegroundColor Red
        Write-Host "Please install Visual Studio 2022 with C++ workload." -ForegroundColor Red
        Write-Host "Download from: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "✓ Found Visual Studio 2022" -ForegroundColor Green

    # Install other dependencies via Chocolatey
    Write-Host "Checking for Chocolatey..."
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    } else {
        Write-Host "✓ Chocolatey already installed" -ForegroundColor Green
    }

    # Install required packages
    Write-Host "Installing required packages via Chocolatey..."
    choco install cmake.install --installargs '"ADD_CMAKE_TO_PATH=System"' -y
    choco install python3 -y
    choco install jdk8 -y

    # Refresh environment
    $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."
    Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
    refreshenv

    Write-Host "✓ System dependencies installed" -ForegroundColor Green
}

if ($DepsOnly) {
    Write-Host ""
    Write-Host "✓ Dependencies-only mode complete" -ForegroundColor Green
    exit 0
}

# Step 2: Download/Install SWIG
Write-Host ""
Write-Host "Step 2: Setting up SWIG..." -ForegroundColor Cyan

# Note: SWIG Windows binary has swig.exe in root directory, not in bin/
$SwigExe = Join-Path $SwigInstall "swig.exe"
if (-not (Test-Path $SwigExe) -or $Force) {
    Write-Host "Downloading SWIG 4.1.1 for Windows..."

    $SwigZip = Join-Path $WorkspaceDir "swig.zip"
    $SwigTmp = Join-Path $WorkspaceDir "swig-tmp"

    # Download
    $ProgressPreference = 'SilentlyContinue'
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "http://prdownloads.sourceforge.net/swig/swigwin-4.1.1.zip" `
        -OutFile $SwigZip -TimeoutSec 300

    # Extract
    if (Test-Path $SwigInstall) {
        Remove-Item -Recurse -Force $SwigInstall
    }
    Expand-Archive -Path $SwigZip -DestinationPath $SwigTmp -Force
    Move-Item (Join-Path $SwigTmp "swigwin-4.1.1") $SwigInstall
    Remove-Item $SwigZip, $SwigTmp -Recurse -Force

    Write-Host "✓ SWIG installed to $SwigInstall" -ForegroundColor Green
} else {
    Write-Host "✓ Using existing SWIG from $SwigInstall" -ForegroundColor Green
}

# Add SWIG to PATH (swig.exe is in the root directory)
$env:PATH = "$SwigInstall;$env:PATH"

# Verify SWIG
$SwigVersion = & swig.exe -version 2>&1 | Select-String "SWIG Version"
Write-Host "  SWIG version: $SwigVersion"

# Check if we have a cached build
$BuildComplete = Join-Path $OpensimInstall ".build_complete"
if ((Test-Path $BuildComplete) -and -not $Force) {
    Write-Host ""
    Write-Host "✓ Using cached OpenSim build from $OpensimInstall" -ForegroundColor Green

    # Verify cache
    $SdkLib = Join-Path $OpensimInstall "sdk\lib"
    if (Test-Path $SdkLib) {
        Write-Host "✓ Cache validation passed" -ForegroundColor Green
        Write-Host ""
        Write-Host "OpenSim is ready! To force rebuild, use: -Force flag" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "Warning: Cache appears corrupted, rebuilding..." -ForegroundColor Yellow
        $Force = $true
    }
}

# Step 3: Build dependencies using CMake preset
Write-Host ""
Write-Host "Step 3: Building OpenSim dependencies..." -ForegroundColor Cyan
Write-Host "This may take 15-20 minutes on first build..." -ForegroundColor Yellow

$DepsBuildDir = Join-Path $WorkspaceDir "dependencies-build"
New-Item -ItemType Directory -Path $DepsBuildDir -Force | Out-Null

Push-Location $DepsBuildDir
try {
    Write-Host "Configuring dependencies with CMake preset '$DepsPreset'..."
    cmake $DepsSource --preset $DepsPreset `
        -DCMAKE_INSTALL_PREFIX="$DepsInstall"

    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed"
    }

    Write-Host "Building dependencies..."
    cmake --build . --config Release -j $Jobs

    if ($LASTEXITCODE -ne 0) {
        throw "Dependencies build failed"
    }

    Write-Host "✓ Dependencies built successfully" -ForegroundColor Green
} finally {
    Pop-Location
}

# Step 4: Build OpenSim core using CMake preset
Write-Host ""
Write-Host "Step 4: Building OpenSim core..." -ForegroundColor Cyan
Write-Host "This may take 20-30 minutes on first build..." -ForegroundColor Yellow

$OpensimBuildDir = Join-Path $WorkspaceDir "opensim-build"
New-Item -ItemType Directory -Path $OpensimBuildDir -Force | Out-Null

Push-Location $OpensimBuildDir
try {
    Write-Host "Configuring OpenSim with CMake preset '$Preset'..."
    cmake $OpensimSource --preset $Preset `
        -DCMAKE_INSTALL_PREFIX="$OpensimInstall" `
        -DOPENSIM_DEPENDENCIES_DIR="$DepsInstall" `
        -DCMAKE_PREFIX_PATH="$DepsInstall" `
        -DSWIG_DIR="$SwigInstall\Lib" `
        -DSWIG_EXECUTABLE="$SwigInstall\swig.exe"

    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed"
    }

    Write-Host "Building OpenSim core..."
    cmake --build . --config Release -j $Jobs

    if ($LASTEXITCODE -ne 0) {
        throw "OpenSim build failed"
    }

    Write-Host "Installing OpenSim..."
    cmake --install .

    if ($LASTEXITCODE -ne 0) {
        throw "OpenSim installation failed"
    }

    # Mark build as complete
    New-Item -ItemType File -Path $BuildComplete -Force | Out-Null

    Write-Host "✓ OpenSim build complete" -ForegroundColor Green
} finally {
    Pop-Location
}

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✓ OpenSim setup complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "OpenSim installed at: $OpensimInstall" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Build Python bindings: make build (or: uv pip install -e .[test])" -ForegroundColor White
Write-Host "  2. Run tests: make test (or: uv run pytest tests/)" -ForegroundColor White
Write-Host ""
Write-Host "Environment variables:" -ForegroundColor Yellow
Write-Host "  OPENSIM_INSTALL_DIR=$OpensimInstall" -ForegroundColor White
Write-Host "  PATH includes SWIG: $SwigInstall" -ForegroundColor White
