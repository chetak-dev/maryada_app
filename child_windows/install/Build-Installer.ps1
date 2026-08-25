<#
.SYNOPSIS
    Builds the single Maryada executable that installs, protects and removes.

.DESCRIPTION
    One self-contained program serves all three roles — setup, protection
    service and child agent — chosen by command line. Publishing it once instead
    of shipping three self-contained programs is what keeps the download small.

.PARAMETER OutputDir
    Where to write the executable. Defaults to child_windows\dist.

.PARAMETER FrameworkDependent
    Builds the small variant instead. Every target PC then needs the
    .NET 8 Desktop Runtime installed.
#>
[CmdletBinding()]
param(
    [string] $OutputDir,
    [switch] $FrameworkDependent
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $RepoRoot 'dist' }
$WorkDir = Join-Path $OutputDir 'build'

function Write-Step($message) { Write-Host "==> $message" -ForegroundColor Cyan }

$publishArgs = @(
    '-c', 'Release',
    '-r', 'win-x64',
    '-p:PublishSingleFile=true',
    '-p:EnableCompressionInSingleFile=true',
    '-p:IncludeNativeLibrariesForSelfExtract=true',
    '-p:DebugType=none',
    '-p:SatelliteResourceLanguages=en',
    '--nologo'
)
if ($FrameworkDependent) {
    $publishArgs += '--self-contained:false'
} else {
    $publishArgs += '--self-contained:true'
}

Write-Step 'Publishing the Maryada program'
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
dotnet publish (Join-Path $RepoRoot 'src\GuardNest.App\GuardNest.App.csproj') `
    @publishArgs -o $WorkDir | Out-Null

$built = Join-Path $WorkDir 'Maryada.exe'
if (-not (Test-Path $built)) { throw 'The Maryada executable was not produced.' }

$version = (Get-Item $built).VersionInfo.ProductVersion
if ($version) { $version = $version.Split('+')[0] } else { $version = '1.0.0' }
$suffix = if ($FrameworkDependent) { '-runtime' } else { '' }
$setupExe = Join-Path $OutputDir "Maryada-Setup-$version$suffix.exe"
Copy-Item $built $setupExe -Force

$sizeMb = [math]::Round((Get-Item $setupExe).Length / 1MB, 1)
$hash = (Get-FileHash $setupExe -Algorithm SHA256).Hash.ToLower()

Write-Host ''
Write-Host "Setup ready: $setupExe  ($sizeMb MB)" -ForegroundColor Green
Write-Host "SHA-256: $hash"
Write-Host ''
Write-Host 'Share this one EXE. The recipient double-clicks it and approves UAC.' -ForegroundColor Yellow
Write-Host 'The same file becomes the protection service and the child agent once installed.'
if ($FrameworkDependent) {
    Write-Host ''
    Write-Host 'This variant needs the .NET 8 Desktop Runtime on every target PC.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'It is not code-signed yet, so SmartScreen may warn on first run.' -ForegroundColor Yellow
