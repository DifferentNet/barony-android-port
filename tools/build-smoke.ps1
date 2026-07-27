[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$Emulator,
    [switch]$BuildGame,
    [switch]$Release,
    [switch]$SignedRelease,
    [ValidateRange(1, 2100000000)]
    [int]$VersionCode = 1,
    [ValidateNotNullOrEmpty()]
    [string]$VersionName = '0.0.1-bootstrap'
)

$ErrorActionPreference = 'Stop'

if ($SignedRelease -and (-not $Release -or -not $BuildGame -or $Emulator)) {
    throw 'SignedRelease requires an ARM64 full-game Release build.'
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

function Get-AsciiBuildRoot {
    param(
        [Parameter(Mandatory)]
        [string]$ActualRoot
    )

    if ($ActualRoot -notmatch '[^\x00-\x7F]') {
        return $ActualRoot
    }

    $AliasParent = Join-Path $env:LOCALAPPDATA 'BaronyAndroidPort'
    $AliasRoot = Join-Path $AliasParent 'workspace'
    New-Item -ItemType Directory -Path $AliasParent -Force | Out-Null

    if (Test-Path -LiteralPath $AliasRoot) {
        $Alias = Get-Item -LiteralPath $AliasRoot -Force
        if (-not ($Alias.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "The Android build alias exists but is not a junction: $AliasRoot"
        }

        $AliasTarget = @($Alias.Target)[0]
        if (-not $AliasTarget) {
            throw "Unable to determine the Android build alias target: $AliasRoot"
        }
        $ResolvedTarget = (Resolve-Path -LiteralPath $AliasTarget).Path
        $ResolvedRoot = (Resolve-Path -LiteralPath $ActualRoot).Path
        if (-not $ResolvedTarget.Equals($ResolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The Android build alias points at a different repository: $ResolvedTarget"
        }
    }
    else {
        New-Item -ItemType Junction -Path $AliasRoot -Target $ActualRoot | Out-Null
    }

    return $AliasRoot
}

if ($BuildGame) {
    $RepositoryRoot = Get-AsciiBuildRoot -ActualRoot $RepositoryRoot
}
$AndroidRoot = Join-Path $RepositoryRoot 'android'
$LocalProperties = Join-Path $AndroidRoot 'local.properties'

function Find-Jdk17 {
    $Candidates = [System.Collections.Generic.List[string]]::new()

    if ($env:JAVA_HOME) {
        $Candidates.Add($env:JAVA_HOME)
    }

    $AdoptiumRoot = Join-Path $env:ProgramFiles 'Eclipse Adoptium'
    if (Test-Path -LiteralPath $AdoptiumRoot) {
        Get-ChildItem -LiteralPath $AdoptiumRoot -Directory -Filter 'jdk-17*' |
            Sort-Object Name -Descending |
            ForEach-Object { $Candidates.Add($_.FullName) }
    }

    foreach ($Candidate in $Candidates) {
        $Java = Join-Path $Candidate 'bin\java.exe'
        if (-not (Test-Path -LiteralPath $Java)) {
            continue
        }

        $VersionOutput = (& $Java --version 2>&1 | Out-String)
        if ($VersionOutput -match '^(?:openjdk|java) 17(?:\.|\s)') {
            return (Resolve-Path -LiteralPath $Candidate).Path
        }
    }

    throw 'JDK 17 was not found. Install Eclipse Temurin 17 with winget and retry.'
}

function Find-AndroidSdk {
    $Candidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { $_ }

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath (Join-Path $Candidate 'platforms\android-36')) {
            return (Resolve-Path -LiteralPath $Candidate).Path
        }
    }

    throw 'Android SDK with platform android-36 was not found.'
}

$Jdk17 = Find-Jdk17
$AndroidSdk = Find-AndroidSdk
$TargetAbi = if ($Emulator) { 'x86_64' } else { 'arm64-v8a' }
$env:JAVA_HOME = $Jdk17
$env:Path = "$(Join-Path $Jdk17 'bin');$env:Path"

$SdkPropertyPath = $AndroidSdk.Replace('\', '/')
Set-Content -LiteralPath $LocalProperties -Value "sdk.dir=$SdkPropertyPath" -Encoding ASCII

Write-Host "Using JDK 17: $Jdk17"
Write-Host "Using Android SDK: $AndroidSdk"
Write-Host "Target ABI: $TargetAbi"
if ($BuildGame) {
    Write-Host "Build repository path: $RepositoryRoot"
}

$GradlePropertyArguments = @("-PbaronyTargetAbi=$TargetAbi")
$GradlePropertyArguments += "-PbaronyVersionCode=$VersionCode"
$GradlePropertyArguments += "-PbaronyVersionName=$VersionName"
if ($BuildGame) {
    $GradlePropertyArguments += '-PbaronyBuildGame=true'
}
if ($SignedRelease) {
    $GradlePropertyArguments += '-PbaronySignedRelease=true'
}
$BuildType = if ($Release) { 'release' } else { 'debug' }
$GradleTask = if ($Release) { ':app:assembleRelease' } else { ':app:assembleDebug' }
$GradleApkName = if ($Release) { 'app-release.apk' } else { 'app-debug.apk' }
$GradleApkPath = Join-Path $AndroidRoot "app\build\outputs\apk\$BuildType\$GradleApkName"

Push-Location $AndroidRoot
try {
    if ($Clean) {
        & .\gradlew.bat clean --no-daemon @GradlePropertyArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle clean failed with exit code $LASTEXITCODE."
        }
    }

    # AGP can reuse an APK container when switching between the full-game and
    # smoke variants, leaving a large stale signing-block gap even though the
    # packaged entries are correct. Removing only the expected output forces a
    # compact package while preserving the native/Gradle incremental caches.
    if (Test-Path -LiteralPath $GradleApkPath) {
        Remove-Item -LiteralPath $GradleApkPath -Force
    }

    & .\gradlew.bat $GradleTask --no-daemon --stacktrace @GradlePropertyArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$ApkPath = $GradleApkPath
if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "Gradle completed without producing the expected APK: $ApkPath"
}

if ($BuildGame) {
    $ArtifactDirectory = Join-Path $AndroidRoot 'artifacts'
    New-Item -ItemType Directory -Path $ArtifactDirectory -Force | Out-Null
    $BaronyApkPath = Join-Path $ArtifactDirectory "app-$BuildType-barony-$TargetAbi.apk"
    Copy-Item -LiteralPath $ApkPath -Destination $BaronyApkPath -Force
    $ApkPath = $BaronyApkPath
}
elseif ($Emulator) {
    $ArtifactDirectory = Join-Path $AndroidRoot 'app\build\artifacts'
    New-Item -ItemType Directory -Path $ArtifactDirectory -Force | Out-Null
    $EmulatorApkPath = Join-Path $ArtifactDirectory 'app-debug-x86_64.apk'
    Copy-Item -LiteralPath $ApkPath -Destination $EmulatorApkPath -Force
    $ApkPath = $EmulatorApkPath
}

$Apk = Get-Item -LiteralPath $ApkPath
$ArtifactLabel = if ($BuildGame) { 'Barony compile-check APK' } else { 'Smoke APK' }
Write-Host "${ArtifactLabel}: $($Apk.FullName) ($($Apk.Length) bytes)"
