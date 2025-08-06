#Requires -RunAsAdministrator
param (
  [switch]$s=$false,
  [switch]$h=$false,
  [string]$d="Release",
  [string]$c="main",
  [int]$j=[int]4
)

# Configuration - use environment variables if set, otherwise use defaults
$DEBUG_TYPE = if ($env:CMAKE_BUILD_TYPE) { $env:CMAKE_BUILD_TYPE } else { "Release" }
$NUM_JOBS = if ($env:CMAKE_BUILD_PARALLEL_LEVEL) { [int]$env:CMAKE_BUILD_PARALLEL_LEVEL } else { 2 }
$OPENSIM_ROOT = Get-Location
$WORKSPACE_DIR = "$OPENSIM_ROOT\build\opensim-workspace"
$MOCO = "off"  # Default MOCO setting

function Help {
    Write-Output "Setting up OpenSim with build type $DEBUG_TYPE, using $NUM_JOBS parallel jobs."
    Write-Output "Usage: setup_opensim_windows.ps1 [-s] [-h] [-d BuildType] [-c Branch] [-j Jobs]"
    Write-Output "  -s          : Disable MOCO (default: enabled)"
    Write-Output "  -h          : Show this help"
    Write-Output "  -d BuildType: Build type (Release, Debug, RelWithDebInfo, MinSizeRel)"
    Write-Output "  -c Branch   : OpenSim core branch to use (default: main)"
    Write-Output "  -j Jobs     : Number of parallel jobs (default: 4)"
    exit
}

# Get flag values if exist.
if ($h) {
    Help
}
if ($s) {
    $MOCO = "off"
} else {
    $MOCO = "on"
}
if ($d -ne "Release" -and $d -ne "Debug" -and $d -ne "RelWithDebInfo" -and $d -ne "MinSizeRel") {
    Write-Error "Value for parameter -d not valid."
    Help
} else {
    $DEBUG_TYPE = $d
}
if ($c) {
    $CORE_BRANCH = $c
}
if ($j -lt [int]1) {
    Write-Error "Value for parameter -j not valid."
    Help
} else {
    $NUM_JOBS = $j
}

Write-Output "Setting up OpenSim with build type: $DEBUG_TYPE using $NUM_JOBS jobs"
Write-Output "DEBUG_TYPE: $DEBUG_TYPE"
Write-Output "NUM_JOBS: $NUM_JOBS"
Write-Output "MOCO: $MOCO"
Write-Output "CORE_BRANCH: $CORE_BRANCH"
Write-Output "WORKSPACE_DIR: $WORKSPACE_DIR"

# create workspace directory
if (-not (Test-Path -Path $WORKSPACE_DIR)) {
    New-Item -ItemType Directory -Path $WORKSPACE_DIR -Force | Out-Null
}

# Cache validation - check if OpenSim is already built and valid
$OPENSIM_COMMIT_HASH = ""
if (Test-Path "$OPENSIM_ROOT\src\opensim-core\.git") {
    try {
        $OPENSIM_COMMIT_HASH = & git -C "$OPENSIM_ROOT\src\opensim-core" rev-parse HEAD 2>$null
        if (-not $OPENSIM_COMMIT_HASH) { $OPENSIM_COMMIT_HASH = "unknown" }
    } catch {
        $OPENSIM_COMMIT_HASH = "unknown"
    }
}
$CACHE_MARKER = "$WORKSPACE_DIR\.opensim_build_complete_$OPENSIM_COMMIT_HASH"

Write-Output "Checking for existing OpenSim build cache..."
if ($env:OPENSIM_CACHE_HIT -eq "true" -and (Test-Path $CACHE_MARKER) -and (Test-Path "$WORKSPACE_DIR\opensim-install\lib\osimCommon.dll")) {
    Write-Output "✓ OpenSim build cache is valid (commit: $($OPENSIM_COMMIT_HASH.Substring(0,8))), skipping rebuild"
    Write-Output "Cache marker found: $CACHE_MARKER"
    exit 0
}

Write-Output "Cache miss or invalid cache, proceeding with OpenSim build..."
if ($OPENSIM_COMMIT_HASH -and $OPENSIM_COMMIT_HASH -ne "unknown") {
    Write-Output "Building for OpenSim commit: $($OPENSIM_COMMIT_HASH.Substring(0,8))"
}

Write-Output "Installing system dependencies..."

# Install chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install Microsoft Visual Studio 2022 Community
choco install visualstudio2022community -y
choco install visualstudio2022-workload-nativedesktop -y
choco install visualstudio2022buildtools -y

# Install cmake 3.23.2
choco install cmake.install --version 3.23.3 --installargs '"ADD_CMAKE_TO_PATH=System"' -y

# Install dependencies of opensim-core
choco install jdk8  -y
choco install swig  -y --version 4.1.1
choco install nsis  -y
py -m pip install numpy

# Refresh choco environment so we can use tools from terminal now.
$env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."   
Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
refreshenv

Write-Output "Building OpenSim dependencies..."

# Generate dependencies project and build dependencies using superbuild
$DEPENDENCIES_BUILD_DIR = "$WORKSPACE_DIR\opensim-dependencies-build"
$DEPENDENCIES_INSTALL_DIR = "$WORKSPACE_DIR\opensim-dependencies-install"

if (-not (Test-Path -Path $DEPENDENCIES_BUILD_DIR)) {
    New-Item -ItemType Directory -Path $DEPENDENCIES_BUILD_DIR -Force | Out-Null
}

Set-Location $DEPENDENCIES_BUILD_DIR

cmake "$OPENSIM_ROOT\opensim-core\dependencies" `
    -G"Visual Studio 17 2022" -A x64 `
    -DCMAKE_INSTALL_PREFIX="$DEPENDENCIES_INSTALL_DIR" `
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE `
    -DSUPERBUILD_ezc3d:BOOL=on `
    -DOPENSIM_WITH_CASADI:BOOL=$MOCO

cmake --build . --config $DEBUG_TYPE -- /maxcpucount:$NUM_JOBS /p:CL_MPCount=1

Write-Output "Building OpenSim core..."

# Generate opensim-core build and build it
$OPENSIM_BUILD_DIR = "$WORKSPACE_DIR\opensim-build"
$OPENSIM_INSTALL_DIR = "$WORKSPACE_DIR\opensim-install"

if (-not (Test-Path -Path $OPENSIM_BUILD_DIR)) {
    New-Item -ItemType Directory -Path $OPENSIM_BUILD_DIR -Force | Out-Null
}

Set-Location $OPENSIM_BUILD_DIR
$env:CXXFLAGS = "/W0 /utf-8 /bigobj"
$env:CL = "/MP1"

cmake "$OPENSIM_ROOT\opensim-core" `
    -G"Visual Studio 17 2022" -A x64 `
    -DCMAKE_INSTALL_PREFIX="$OPENSIM_INSTALL_DIR" `
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE `
    -DOPENSIM_DEPENDENCIES_DIR="$DEPENDENCIES_INSTALL_DIR" `
    -DBUILD_JAVA_WRAPPING=OFF `
    -DBUILD_PYTHON_WRAPPING=OFF `
    -DBUILD_TESTING=OFF `
    -DOPENSIM_C3D_PARSER=ezc3d `
    -DOPENSIM_WITH_CASADI:BOOL=$MOCO `
    -DOPENSIM_INSTALL_UNIX_FHS=OFF

cmake --build . --config $DEBUG_TYPE -- /maxcpucount:$NUM_JOBS /p:CL_MPCount=1
cmake --install .

# Create cache completion marker
if ($OPENSIM_COMMIT_HASH -and $OPENSIM_COMMIT_HASH -ne "unknown") {
    New-Item -ItemType File -Path $CACHE_MARKER -Force | Out-Null
    Write-Output "✓ Cache marker created: $CACHE_MARKER"
}

Write-Output "OpenSim setup complete. Libraries installed in: $OPENSIM_INSTALL_DIR"