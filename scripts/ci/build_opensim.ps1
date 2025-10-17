# CI-specific OpenSim build orchestrator for Windows
# This script wraps the setup script with CI-specific caching and path handling
#
# Usage:
#   build_opensim.ps1 -CacheDir <path> [-Force] [-Jobs <n>]
#
# Environment variables expected from CI:
#   OPENSIM_SHA: Git SHA of opensim-core submodule (for cache validation)

param(
    [Parameter(Mandatory=$true)]
    [string]$CacheDir,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [int]$Jobs = $env:NUMBER_OF_PROCESSORS
)

$ErrorActionPreference = "Stop"

# Get script directory and project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

Write-Host "=== CI OpenSim Build for Windows ===" -ForegroundColor Cyan
Write-Host "Cache dir: $CacheDir"
Write-Host "Jobs: $Jobs"
Write-Host "Force rebuild: $Force"

# Set up paths
$OpensimInstall = Join-Path $CacheDir "opensim-install"
$DepsInstall = Join-Path $CacheDir "dependencies-install"
$SwigInstall = Join-Path $CacheDir "swig"

# Check if we have a cached build
$BuildComplete = Join-Path $OpensimInstall ".build_complete"
if ((Test-Path $BuildComplete) -and -not $Force) {
    Write-Host "✓ Using cached OpenSim build from $OpensimInstall" -ForegroundColor Green

    # Verify cache is valid
    $SdkLib = Join-Path $OpensimInstall "sdk\lib"
    if (Test-Path $SdkLib) {
        Write-Host "✓ Cache validation passed" -ForegroundColor Green
        Get-ChildItem $SdkLib -File | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "Warning: Cache appears corrupted, rebuilding..." -ForegroundColor Yellow
        $Force = $true
    }
}

if ($Force -or -not (Test-Path $BuildComplete)) {
    Write-Host "Building OpenSim from scratch..." -ForegroundColor Yellow

    # Create cache directory
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

    # Step 1: Visual Studio Environment
    # NOTE: In GitHub Actions with cibuildwheel, VS environment is already set up
    Write-Host ""
    Write-Host "Step 1: Checking Visual Studio environment..." -ForegroundColor Cyan

    # Verify we have a C++ compiler
    try {
        $ClVersion = & cl.exe 2>&1 | Select-String "Version"
        Write-Host "✓ Visual Studio compiler found: $ClVersion" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Visual Studio compiler not found. Ensure VS 2022 is installed." -ForegroundColor Red
        exit 1
    }

    # Step 2: Install/Download SWIG
    Write-Host ""
    Write-Host "Step 2: Setting up SWIG..." -ForegroundColor Cyan

    # Note: SWIG Windows binary has swig.exe in root directory, not in bin/
    $SwigExe = Join-Path $SwigInstall "swig.exe"
    if (-not (Test-Path $SwigExe)) {
        Write-Host "Downloading SWIG 4.1.1 for Windows..."
        $SwigZip = Join-Path $CacheDir "swig.zip"

        # Download with progress
        $ProgressPreference = 'SilentlyContinue'
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "http://prdownloads.sourceforge.net/swig/swigwin-4.1.1.zip" `
            -OutFile $SwigZip -TimeoutSec 300

        # Extract
        $SwigTmp = Join-Path $CacheDir "swig-tmp"
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

    # Step 3: Build dependencies using CMake presets
    Write-Host ""
    Write-Host "Step 3: Building OpenSim dependencies..." -ForegroundColor Cyan

    $DepsSource = Join-Path $ProjectRoot "src\opensim-core\dependencies"
    $DepsBuildDir = Join-Path $CacheDir "dependencies-build"
    New-Item -ItemType Directory -Path $DepsBuildDir -Force | Out-Null

    Push-Location $DepsBuildDir
    try {
        Write-Host "Configuring dependencies with CMake preset 'opensim-dependencies-windows'..."
        cmake $DepsSource --preset opensim-dependencies-windows `
            -DCMAKE_INSTALL_PREFIX="$DepsInstall"

        if ($LASTEXITCODE -ne 0) {
            throw "CMake configuration failed with exit code $LASTEXITCODE"
        }

        # Build with periodic output to prevent timeout detection
        Write-Host "Building dependencies (this may take 15-20 minutes)..."

        $buildJob = Start-Job -ScriptBlock {
            param($BuildDir, $Jobs)
            Set-Location $BuildDir
            cmake --build . --config Release -j $Jobs 2>&1
        } -ArgumentList $DepsBuildDir, $Jobs

        # Monitor job and provide periodic output
        while ($buildJob.State -eq 'Running') {
            Start-Sleep -Seconds 30
            Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] Dependencies build in progress..."
            Receive-Job $buildJob # Show any new output
        }

        # Wait for completion and get final result
        $buildJob | Wait-Job | Receive-Job
        $exitCode = $buildJob.ChildJobs[0].Output | Select-Object -Last 1
        Remove-Job $buildJob

        if ($LASTEXITCODE -ne 0) {
            throw "Dependencies build failed with exit code $LASTEXITCODE"
        }

        Write-Host "✓ Dependencies built successfully" -ForegroundColor Green
    } finally {
        Pop-Location
    }

    # Step 4: Build OpenSim core using CMake presets
    Write-Host ""
    Write-Host "Step 4: Building OpenSim core..." -ForegroundColor Cyan

    $OpensimSource = Join-Path $ProjectRoot "src\opensim-core"
    $OpensimBuildDir = Join-Path $CacheDir "opensim-build"
    New-Item -ItemType Directory -Path $OpensimBuildDir -Force | Out-Null

    Push-Location $OpensimBuildDir
    try {
        Write-Host "Configuring OpenSim with CMake preset 'opensim-core-windows'..."
        cmake $OpensimSource --preset opensim-core-windows `
            -DCMAKE_INSTALL_PREFIX="$OpensimInstall" `
            -DOPENSIM_DEPENDENCIES_DIR="$DepsInstall" `
            -DCMAKE_PREFIX_PATH="$DepsInstall" `
            -DSWIG_DIR="$SwigInstall\Lib" `
            -DSWIG_EXECUTABLE="$SwigInstall\swig.exe"

        if ($LASTEXITCODE -ne 0) {
            throw "CMake configuration failed with exit code $LASTEXITCODE"
        }

        # Build with periodic output to prevent timeout detection
        Write-Host "Building OpenSim core (this may take 20-30 minutes)..."

        $buildJob = Start-Job -ScriptBlock {
            param($BuildDir, $Jobs)
            Set-Location $BuildDir
            cmake --build . --config Release -j $Jobs 2>&1
        } -ArgumentList $OpensimBuildDir, $Jobs

        # Monitor job and provide periodic output
        while ($buildJob.State -eq 'Running') {
            Start-Sleep -Seconds 30
            Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] OpenSim core build in progress..."
            Receive-Job $buildJob # Show any new output
        }

        # Wait for completion and get final result
        $buildJob | Wait-Job | Receive-Job
        $exitCode = $buildJob.ChildJobs[0].Output | Select-Object -Last 1
        Remove-Job $buildJob

        if ($LASTEXITCODE -ne 0) {
            throw "OpenSim build failed with exit code $LASTEXITCODE"
        }

        # Install
        Write-Host "Installing OpenSim..."
        cmake --install .

        if ($LASTEXITCODE -ne 0) {
            throw "OpenSim installation failed with exit code $LASTEXITCODE"
        }

        # Mark build as complete
        New-Item -ItemType File -Path $BuildComplete -Force | Out-Null

        Write-Host "✓ OpenSim build complete" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# Set environment variables for subsequent build steps
Write-Host ""
Write-Host "Setting up build environment..." -ForegroundColor Cyan
$env:PATH = "$SwigInstall;$env:PATH"
$env:OPENSIM_INSTALL_DIR = $OpensimInstall

Write-Host "  PATH includes SWIG: $(if (Get-Command swig.exe -ErrorAction SilentlyContinue) { 'Yes' } else { 'No' })"
Write-Host "  OPENSIM_INSTALL_DIR: $env:OPENSIM_INSTALL_DIR"

# Verify SWIG is working
Write-Host "  SWIG version check:"
try {
    & swig.exe -version 2>&1 | Select-String "SWIG Version" | ForEach-Object { Write-Host "    $_" }
} catch {
    Write-Host "    ERROR: SWIG not working" -ForegroundColor Red
}

Write-Host ""
Write-Host "✓ CI build environment ready" -ForegroundColor Green
Write-Host "  OpenSim installed at: $OpensimInstall" -ForegroundColor Green
