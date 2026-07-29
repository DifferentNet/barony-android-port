[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BackupPath,
    [string]$Serial,
    [string]$ExpectedVersionName = '5.0.2-android-rc1',
    [ValidateRange(10, 180)][int]$StartupTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$PackageName = 'com.zhdan.baronyport'
$LauncherComponent = "$PackageName/.BaronyActivity"
$RemoteStage = "/sdcard/Android/data/$PackageName/files/barony-state-import"
$ExpectedRemoteStage = "/sdcard/Android/data/$PackageName/files/barony-state-import"
if ($RemoteStage -ne $ExpectedRemoteStage) {
    throw "Refusing to use unexpected device staging path: $RemoteStage"
}

$BackupPath = (Resolve-Path -LiteralPath $BackupPath).Path
$ManifestPath = Join-Path $BackupPath 'manifest.json'
$PayloadRoot = Join-Path $BackupPath 'payload'
if ((-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) -or
        (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container))) {
    throw "Invalid Barony state backup directory: $BackupPath"
}
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($Manifest.schemaVersion -ne 1 -or $Manifest.packageName -ne $PackageName) {
    throw 'The state backup manifest schema or package name is incompatible.'
}

$ManifestFiles = @{}
foreach ($Property in $Manifest.files.PSObject.Properties) {
    $ManifestFiles[$Property.Name] = [string]$Property.Value
}
$LocalFiles = @(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File | Sort-Object FullName)
if ($LocalFiles.Count -ne $ManifestFiles.Count -or $LocalFiles.Count -eq 0) {
    throw 'The backup payload file count does not match its manifest.'
}
$PayloadPrefix = [IO.Path]::GetFullPath($PayloadRoot).TrimEnd('\') + '\'
foreach ($File in $LocalFiles) {
    $FullFilePath = [IO.Path]::GetFullPath($File.FullName)
    if (-not $FullFilePath.StartsWith($PayloadPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup file escaped the payload directory: $FullFilePath"
    }
    $RelativePath = $FullFilePath.Substring($PayloadPrefix.Length).Replace('\', '/')
    if ($RelativePath -notmatch '^(savegames|config)/[^/].*' -or -not $ManifestFiles.ContainsKey($RelativePath)) {
        throw "Unexpected or unlisted backup path: $RelativePath"
    }
    $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Hash -ne $ManifestFiles[$RelativePath].ToLowerInvariant()) {
        throw "Backup integrity check failed for $RelativePath"
    }
}

$AndroidSdk = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
} elseif ($env:ANDROID_HOME) {
    $env:ANDROID_HOME
} else {
    Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}
$Adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $Adb)) {
    throw "ADB was not found at $Adb"
}

function Get-ConnectedDevices {
    $Lines = @(& $Adb devices 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list ADB devices: $($Lines -join [Environment]::NewLine)"
    }
    return @($Lines | ForEach-Object {
        if ($_ -match '^(.+?)\s+device(?:\s|$)') { $Matches[1].Trim() }
    })
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $PreviousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $Output = @(& $Adb -s $script:TargetSerial @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $PreviousErrorPreference
    }
    $script:LastAdbExitCode = $ExitCode
    if ($ExitCode -ne 0 -and -not $AllowFailure) {
        throw "ADB command failed (exit $ExitCode): adb -s $script:TargetSerial $($Arguments -join ' ')`n$($Output -join [Environment]::NewLine)"
    }
    return $Output
}

$ConnectedDevices = @(Get-ConnectedDevices)
if ($Serial) {
    if ($ConnectedDevices -notcontains $Serial) {
        throw "ADB target '$Serial' is not connected. Available: $($ConnectedDevices -join ', ')"
    }
    $TargetSerial = $Serial
} elseif ($ConnectedDevices.Count -eq 1) {
    $TargetSerial = $ConnectedDevices[0]
} elseif ($ConnectedDevices.Count -eq 0) {
    throw 'No usable Android device is connected.'
} else {
    throw "More than one ADB target is connected. Pass -Serial with one of: $($ConnectedDevices -join ', ')"
}

$PackageDump = @(Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $PackageName)) -join "`n"
if ($PackageDump -notmatch "versionName=$([Regex]::Escape($ExpectedVersionName))(?:\s|$)") {
    throw "Expected installed Barony version $ExpectedVersionName before restoring state."
}

Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $PackageName) | Out-Null
Invoke-Adb -Arguments @('shell', 'rm', '-rf', $RemoteStage) | Out-Null
Invoke-Adb -Arguments @('shell', 'mkdir', '-p', "$RemoteStage/payload") | Out-Null

foreach ($File in $LocalFiles) {
    $FullFilePath = [IO.Path]::GetFullPath($File.FullName)
    $RelativePath = $FullFilePath.Substring($PayloadPrefix.Length).Replace('\', '/')
    $RemoteFile = "$RemoteStage/payload/$RelativePath"
    $RemoteParent = $RemoteFile.Substring(0, $RemoteFile.LastIndexOf('/'))
    Invoke-Adb -Arguments @('shell', 'mkdir', '-p', $RemoteParent) | Out-Null
    Invoke-Adb -Arguments @('push', $File.FullName, $RemoteFile) | Out-Null
    $RemoteHashOutput = @(Invoke-Adb -Arguments @('shell', 'sha256sum', $RemoteFile)) -join ' '
    if (($RemoteHashOutput -notmatch '^([0-9a-fA-F]{64})\s') -or
            ($Matches[1].ToLowerInvariant() -ne $ManifestFiles[$RelativePath].ToLowerInvariant())) {
        throw "Device staging integrity check failed for $RelativePath"
    }
}
Invoke-Adb -Arguments @('push', $ManifestPath, "$RemoteStage/manifest.json") | Out-Null

Invoke-Adb -Arguments @('logcat', '-c') | Out-Null
Invoke-Adb -Arguments @('shell', 'am', 'start', '-W', '-n', $LauncherComponent) | Out-Null
$Deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
$ImportComplete = $false
$MainMenuReady = $false
do {
    Start-Sleep -Seconds 2
    $Log = @(Invoke-Adb -Arguments @('logcat', '-d', '-v', 'brief')) -join "`n"
    if ($Log -match 'BARONY_ANDROID_STATE_IMPORT_FAILED') {
        throw 'The app rejected the staged state backup. It remains on the device for diagnosis.'
    }
    $ImportComplete = $Log -match 'BARONY_ANDROID_STATE_IMPORT_COMPLETE'
    $MainMenuReady = $Log -match 'BARONY_ANDROID_MAIN_MENU_READY'
} while ((-not $ImportComplete -or -not $MainMenuReady) -and [DateTime]::UtcNow -lt $Deadline)

if (-not $ImportComplete) {
    throw 'Timed out waiting for BARONY_ANDROID_STATE_IMPORT_COMPLETE.'
}
if (-not $MainMenuReady) {
    throw 'State restored, but the game did not reach BARONY_ANDROID_MAIN_MENU_READY in time.'
}

$RemainingManifest = @(Invoke-Adb -Arguments @(
    'shell', 'test', '-e', "$RemoteStage/manifest.json"
) -AllowFailure)
if ($LastAdbExitCode -eq 0) {
    throw 'The app reported restore success but did not consume the import manifest.'
}

Write-Host "Restored and revalidated $($LocalFiles.Count) Barony state files on $TargetSerial."
Write-Host 'Barony app reached the main menu and consumed the staged import.'
