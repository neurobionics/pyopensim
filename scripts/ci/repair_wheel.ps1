<#
    Wrapper invoked by cibuildwheel to run delvewheel with all OpenSim DLL directories.
    Parameters are passed in from pyproject.toml.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Wheel,

    [Parameter(Mandatory = $true)]
    [string]$Dest,

    [string[]]$AdditionalPaths
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command delvewheel -ErrorAction SilentlyContinue)) {
    throw "delvewheel executable not found on PATH"
}

$cache = $env:OPENSIM_CACHE_DIR
if (-not $cache) {
    throw "OPENSIM_CACHE_DIR environment variable is not set"
}

Write-Host "[delvewheel] Cache root: $cache"
Write-Host "[delvewheel] Wheel: $Wheel"
Write-Host "[delvewheel] Destination: $Dest"

$candidatePaths = @(
    Join-Path $cache 'opensim-install\bin',
    Join-Path $cache 'opensim-install\sdk\bin',
    Join-Path $cache 'opensim-install\sdk\Simbody\bin',
    Join-Path $cache 'dependencies-install\bin',
    Join-Path $cache 'dependencies-install\simbody\bin',
    Join-Path $cache 'dependencies-install\ezc3d\bin'
)

if ($AdditionalPaths) {
    $candidatePaths += $AdditionalPaths
}

$existingPaths = @()
foreach ($path in $candidatePaths) {
    if (Test-Path $path) {
        $resolved = (Resolve-Path -LiteralPath $path).Path
        $existingPaths += $resolved
        Write-Host "[delvewheel] Using path: $resolved"
    } else {
        Write-Host "[delvewheel] Skipping missing path: $path"
    }
}

if (-not $existingPaths) {
    Write-Warning "[delvewheel] No dependency directories found; wheel repair likely to fail"
}

$args = @('repair', '-w', $Dest, $Wheel)
foreach ($path in $existingPaths) {
    $args += '--add-path'
    $args += $path
}

Write-Host "[delvewheel] Executing: delvewheel $($args -join ' ')"
& delvewheel @args

if ($LASTEXITCODE -ne 0) {
    throw "delvewheel repair failed with exit code $LASTEXITCODE"
}
