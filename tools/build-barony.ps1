[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$Emulator
)

$ErrorActionPreference = 'Stop'

$BuildSmoke = Join-Path $PSScriptRoot 'build-smoke.ps1'
& $BuildSmoke -Clean:$Clean -Emulator:$Emulator -BuildGame
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
