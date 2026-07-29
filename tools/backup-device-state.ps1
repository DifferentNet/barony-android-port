[CmdletBinding()]
param(
    [string]$Serial,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$PackageName = 'com.zhdan.baronyport'
$RemoteStage = "/sdcard/Android/data/$PackageName/files/barony-state-export"
$ExpectedRemoteStage = "/sdcard/Android/data/$PackageName/files/barony-state-export"
if ($RemoteStage -ne $ExpectedRemoteStage) {
    throw "Refusing to use unexpected device staging path: $RemoteStage"
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

$RunAsProbe = @(Invoke-Adb -Arguments @('shell', 'run-as', $PackageName, 'id') -AllowFailure)
if ($LastAdbExitCode -ne 0 -or ($RunAsProbe -join '') -notmatch 'uid=') {
    throw 'The installed app is not a debuggable Barony build; run-as backup is unavailable.'
}
foreach ($RelativeSource in @('savegames', 'config')) {
    Invoke-Adb -Arguments @(
        'shell', 'run-as', $PackageName, 'test', '-d',
        "files/barony-output/$RelativeSource"
    ) | Out-Null
}

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SafeSerial = $TargetSerial -replace '[^A-Za-z0-9_.-]', '_'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepositoryRoot "android\device-backups\$Timestamp-$SafeSerial"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Backup destination already exists: $OutputDirectory"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$Completed = $false
try {
    Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $PackageName, 'rm', '-rf', $RemoteStage) | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $PackageName, 'mkdir', '-p', "$RemoteStage/payload") | Out-Null
    foreach ($RelativeSource in @('savegames', 'config')) {
        Invoke-Adb -Arguments @(
            'shell', 'run-as', $PackageName, 'cp', '-R',
            "files/barony-output/$RelativeSource", "$RemoteStage/payload/"
        ) | Out-Null
    }
    Invoke-Adb -Arguments @(
        'shell', 'run-as', $PackageName, 'chmod', '-R', '0755', $RemoteStage
    ) | Out-Null

    Invoke-Adb -Arguments @('pull', "$RemoteStage/payload", $OutputDirectory) | Out-Null
    $PayloadRoot = Join-Path $OutputDirectory 'payload'
    if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) {
        throw 'ADB completed without producing the expected backup payload directory.'
    }

    $Files = @(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File | Sort-Object FullName)
    if ($Files.Count -eq 0) {
        throw 'The device backup contains no files.'
    }
    $FileHashes = [ordered]@{}
    $TotalBytes = 0L
    $PayloadPrefix = [IO.Path]::GetFullPath($PayloadRoot).TrimEnd('\') + '\'
    foreach ($File in $Files) {
        $FullFilePath = [IO.Path]::GetFullPath($File.FullName)
        if (-not $FullFilePath.StartsWith($PayloadPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Backup file escaped the payload directory: $FullFilePath"
        }
        $RelativePath = $FullFilePath.Substring($PayloadPrefix.Length).Replace('\', '/')
        if ($RelativePath -notmatch '^(savegames|config)/[^/].*') {
            throw "Unexpected backup path: $RelativePath"
        }
        $LocalHash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $RemoteHashOutput = @(Invoke-Adb -Arguments @(
            'shell', 'run-as', $PackageName, 'sha256sum', "$RemoteStage/payload/$RelativePath"
        )) -join ' '
        if ($RemoteHashOutput -notmatch '^([0-9a-fA-F]{64})\s') {
            throw "Unable to read the device hash for $RelativePath"
        }
        if ($LocalHash -ne $Matches[1].ToLowerInvariant()) {
            throw "Backup transfer integrity check failed for $RelativePath"
        }
        $FileHashes[$RelativePath] = $LocalHash
        $TotalBytes += $File.Length
    }

    $PackageDump = @(Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $PackageName)) -join "`n"
    $VersionName = if ($PackageDump -match 'versionName=([^\s]+)') { $Matches[1] } else { '<unknown>' }
    $Manifest = [ordered]@{
        schemaVersion = 1
        packageName = $PackageName
        backupId = "$Timestamp-$SafeSerial"
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceSerial = $TargetSerial
        sourceVersionName = $VersionName
        fileCount = $Files.Count
        totalBytes = $TotalBytes
        files = $FileHashes
    }
    $ManifestPath = Join-Path $OutputDirectory 'manifest.json'
    $Json = $Manifest | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($ManifestPath, $Json, [Text.UTF8Encoding]::new($false))
    $ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.sha256') `
        -Value "$ManifestHash  manifest.json" -Encoding ASCII

    $Completed = $true
    Write-Host "Verified Barony state backup: $OutputDirectory"
    Write-Host "Files: $($Files.Count), bytes: $TotalBytes, source version: $VersionName"
    Write-Host "Manifest SHA-256: $ManifestHash"
}
finally {
    Invoke-Adb -Arguments @('shell', 'run-as', $PackageName, 'rm', '-rf', $RemoteStage) -AllowFailure | Out-Null
    if (-not $Completed -and (Test-Path -LiteralPath $OutputDirectory)) {
        $BackupRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'android\device-backups'))
        if ($OutputDirectory.StartsWith($BackupRoot + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
        }
    }
}
