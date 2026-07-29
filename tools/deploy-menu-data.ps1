[CmdletBinding()]
param(
    [string]$SourcePath = 'C:\Program Files (x86)\Steam\steamapps\common\Barony',
    [string]$Serial
)

$ErrorActionPreference = 'Stop'

$ExpectedGameVersion = '5.0.2'
$ExpectedSourceCommit = '962a5ce36d10207beef7d8673876e0cebf8e76e4'
$ManifestName = '.barony-android-data.json'
$DlcUnlockName = 'dlc.unlock'
$DlcKeyMaximumBytes = 4096
$DlcDefinitions = @(
    [pscustomobject]@{
        Pack = 'mythsandoutcasts'
        Name = 'Myths and Outcasts'
        AppId = '1010820'
        KeyFile = 'mythsandoutcasts.key'
    },
    [pscustomobject]@{
        Pack = 'legendsandpariahs'
        Name = 'Legends and Pariahs'
        AppId = '1010821'
        KeyFile = 'legendsandpariahs.key'
    },
    [pscustomobject]@{
        Pack = 'desertersanddisciples'
        Name = 'Deserters and Disciples'
        AppId = '1010822'
        KeyFile = 'desertersanddisciples.key'
    }
)
$RequiredDirectories = @('books', 'data', 'fonts', 'images', 'items', 'lang', 'maps', 'models', 'music', 'sound')
$RequiredFiles = @(
    'gamecontrollerdb.txt',
    'npcnames-female.txt',
    'npcnames-male.txt',
    'playernames-female.txt',
    'playernames-male.txt'
)
$ExpectedCriticalHashes = [ordered]@{
    'lang/en.txt' = '153ef608caafea9226db4e006ad8d778bfe675cf006227efe0fb5c5cac551f40'
    'maps/start.lmp' = '40a57fb4e5b1caed5f03599077db368f414970ebcd9aa169fdaeabeb9e6bf04d'
    'models/models.txt' = 'd5344cb2891baf871d8a09aa25aeeefb60cb633f4c1a327e46d40d823bdd949c'
    'sound/sounds.txt' = 'f4da80b451d4023323f33e8edc555ef0698de2e46629fd7b710aab5f7cd7eb1e'
}
$CriticalFiles = @($ExpectedCriticalHashes.Keys)

function Get-SteamRootCandidates {
    param([Parameter(Mandatory)][string]$InstallPath)

    $Candidates = [System.Collections.Generic.List[string]]::new()
    if ($InstallPath -match '(?i)[\\/]steamapps[\\/]common[\\/]') {
        $Candidates.Add([IO.Path]::GetFullPath(
            (Join-Path $InstallPath '..\..\..')))
    }
    foreach ($RegistryPath in @(
            'HKCU:\Software\Valve\Steam',
            'HKLM:\Software\WOW6432Node\Valve\Steam',
            'HKLM:\Software\Valve\Steam')) {
        try {
            $Properties = Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction Stop
            foreach ($PropertyName in @('SteamPath', 'InstallPath')) {
                $Property = $Properties.PSObject.Properties[$PropertyName]
                $Value = if ($Property) { $Property.Value } else { $null }
                if ($Value) {
                    $Candidates.Add([IO.Path]::GetFullPath($Value))
                }
            }
        }
        catch {
        }
    }
    $Candidates.Add('C:\Program Files (x86)\Steam')
    $Candidates.Add('C:\Program Files\Steam')

    return @(
        $Candidates |
            Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
            Select-Object -Unique
    )
}

function Test-SteamCachedAppTicket {
    param(
        [Parameter(Mandatory)][string[]]$SteamRoots,
        [Parameter(Mandatory)][string]$AppId
    )

    foreach ($SteamRoot in $SteamRoots) {
        $UserData = Join-Path $SteamRoot 'userdata'
        if (-not (Test-Path -LiteralPath $UserData -PathType Container)) {
            continue
        }
        $Configs = @(
            Get-ChildItem -LiteralPath $UserData -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'config\localconfig.vdf' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        )
        foreach ($Config in $Configs) {
            $InTickets = $false
            $BlockOpened = $false
            foreach ($Line in [IO.File]::ReadLines($Config)) {
                $Trimmed = $Line.Trim()
                if (-not $InTickets) {
                    if ($Trimmed -eq '"apptickets"') {
                        $InTickets = $true
                    }
                    continue
                }
                if (-not $BlockOpened) {
                    if ($Trimmed -eq '{') {
                        $BlockOpened = $true
                    }
                    continue
                }
                if ($Trimmed -eq '}') {
                    break
                }
                if ($Trimmed -match ('^"' + [regex]::Escape($AppId) + '"(?:\s|$)')) {
                    return $true
                }
            }
        }
    }
    return $false
}

foreach ($relativePath in $RequiredDirectories + $RequiredFiles + $CriticalFiles) {
    $candidate = Join-Path $SourcePath $relativePath
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Owned Barony data is incomplete; missing: $candidate"
    }
}

$SourceCheckout = Join-Path $SourcePath '_barony-source'
if (Test-Path -LiteralPath (Join-Path $SourceCheckout '.git')) {
    $ActualSourceCommit = (& git.exe -C $SourceCheckout rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $ActualSourceCommit) {
        throw "Unable to read the installed Barony source revision from $SourceCheckout"
    }
    if ($ActualSourceCommit -ne $ExpectedSourceCommit) {
        throw "Unsupported Barony data version. Expected v$ExpectedGameVersion source $ExpectedSourceCommit, found $ActualSourceCommit."
    }
    Write-Host "Validated installed source commit $ActualSourceCommit."
}

foreach ($relativePath in $CriticalFiles) {
    $ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $SourcePath $relativePath)).Hash.ToLowerInvariant()
    if ($ActualHash -ne $ExpectedCriticalHashes[$relativePath]) {
        throw "Unsupported or modified Barony data file: $relativePath. Expected data from Barony v$ExpectedGameVersion."
    }
}
Write-Host "Validated owned Barony v$ExpectedGameVersion data using pinned critical-file hashes."

$SourceType = if ($SourcePath -match '(?i)steamapps[\\/]common') {
    'steam'
}
elseif ($SourcePath -match '(?i)gog') {
    'gog'
}
else {
    'custom'
}
$SteamRoots = if ($SourceType -eq 'steam') {
    @(Get-SteamRootCandidates -InstallPath $SourcePath)
}
else {
    @()
}
$DlcEntitlements = [System.Collections.Generic.List[object]]::new()
$SteamUnlockedPacks = [System.Collections.Generic.List[string]]::new()
foreach ($Dlc in $DlcDefinitions) {
    $KeyPath = Join-Path $SourcePath $Dlc.KeyFile
    $KeyPresent = Test-Path -LiteralPath $KeyPath -PathType Leaf
    if ($KeyPresent) {
        $KeyFile = Get-Item -LiteralPath $KeyPath
        if ($KeyFile.Length -le 0 -or $KeyFile.Length -gt $DlcKeyMaximumBytes) {
            throw "DLC key file has an invalid size: $($Dlc.KeyFile)"
        }
    }
    $SteamTicket = $false
    if ($SourceType -eq 'steam') {
        $SteamTicket = Test-SteamCachedAppTicket `
            -SteamRoots $SteamRoots `
            -AppId $Dlc.AppId
    }
    if ($SteamTicket) {
        $SteamUnlockedPacks.Add($Dlc.Pack)
        $DlcEntitlements.Add([ordered]@{
            pack = $Dlc.Pack
            source = 'steam-cached-ticket'
        })
        Write-Host "DLC entitlement: $($Dlc.Name) (cached Steam ticket)."
    }
    elseif ($KeyPresent) {
        $DlcEntitlements.Add([ordered]@{
            pack = $Dlc.Pack
            source = 'key-file'
        })
        Write-Host "DLC entitlement: $($Dlc.Name) (license key; validated by Barony)."
    }
    else {
        Write-Host "DLC entitlement not detected: $($Dlc.Name)."
    }
}

$AndroidSdk = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
}
else {
    Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}
$Adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $Adb)) {
    throw "ADB was not found at $Adb"
}
$AdbArguments = @()
if ($Serial) {
    $AdbArguments += @('-s', $Serial)
}

& $Adb @AdbArguments get-state | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'No usable Android device or emulator is connected.'
}
& $Adb @AdbArguments shell pm path com.zhdan.baronyport | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Install the Barony Android APK before deploying data.'
}

$TemporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$StagingRoot = [IO.Path]::GetFullPath((Join-Path $TemporaryBase 'BaronyAndroidPortMenuData'))
if (-not $StagingRoot.StartsWith($TemporaryBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use staging path outside the temporary directory: $StagingRoot"
}
if (Test-Path -LiteralPath $StagingRoot) {
    Remove-Item -LiteralPath $StagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingRoot | Out-Null

try {
    foreach ($directory in $RequiredDirectories) {
        $source = Join-Path $SourcePath $directory
        $destination = Join-Path $StagingRoot $directory
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $robocopyArguments = @($source, $destination, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
        if ($directory -eq 'data') {
            $robocopyArguments += @('/XF', '*.ogv')
        }
        & robocopy.exe @robocopyArguments | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Failed to stage Barony data directory: $directory (robocopy exit $LASTEXITCODE)"
        }
    }
    foreach ($file in $RequiredFiles) {
        Copy-Item -LiteralPath (Join-Path $SourcePath $file) -Destination (Join-Path $StagingRoot $file)
    }
    foreach ($Dlc in $DlcDefinitions) {
        $KeyPath = Join-Path $SourcePath $Dlc.KeyFile
        if (Test-Path -LiteralPath $KeyPath -PathType Leaf) {
            Copy-Item -LiteralPath $KeyPath -Destination (
                Join-Path $StagingRoot $Dlc.KeyFile)
        }
    }
    if ($SteamUnlockedPacks.Count -gt 0) {
        $UnlockLines = @(
            '# Barony Android DLC entitlements detected from cached Steam app tickets.'
            'format=1'
        ) + @($SteamUnlockedPacks)
        [IO.File]::WriteAllText(
            (Join-Path $StagingRoot $DlcUnlockName),
            (($UnlockLines -join "`n") + "`n"),
            (New-Object Text.UTF8Encoding($false)))
    }

    $CriticalHashes = [ordered]@{}
    foreach ($relativePath in $CriticalFiles) {
        $CriticalHashes[$relativePath] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $StagingRoot $relativePath)).Hash.ToLowerInvariant()
    }
    $StagedFiles = @(Get-ChildItem -LiteralPath $StagingRoot -Recurse -File)
    $StagedSize = ($StagedFiles | Measure-Object Length -Sum).Sum
    $Manifest = [ordered]@{
        schemaVersion = 1
        gameVersion = $ExpectedGameVersion
        sourceCommit = $ExpectedSourceCommit
        deployedAtUtc = [DateTime]::UtcNow.ToString('o')
        deploymentMethod = 'windows-adb-installer-v3'
        sourceType = $SourceType
        fileCount = $StagedFiles.Count
        uncompressedBytes = $StagedSize
        criticalFiles = $CriticalHashes
        dlcEntitlements = @($DlcEntitlements)
    }
    $ManifestPath = Join-Path $StagingRoot $ManifestName
    $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText(
        $ManifestPath,
        ($Manifest | ConvertTo-Json -Depth 4),
        $Utf8WithoutBom)

    $Archive = Join-Path $TemporaryBase 'barony-menu-data.tar.gz'
    if (Test-Path -LiteralPath $Archive) {
        Remove-Item -LiteralPath $Archive -Force
    }
    & tar.exe -czf $Archive -C $StagingRoot .
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to create the temporary Barony data archive.'
    }

    $RemoteArchive = '/data/local/tmp/barony-menu-data.tar.gz'
    $RemoteData = '/sdcard/Android/data/com.zhdan.baronyport/files/barony-data'
    & $Adb @AdbArguments push $Archive $RemoteArchive
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to upload the Barony data archive.'
    }
    & $Adb @AdbArguments shell "mkdir -p '$RemoteData' && tar -xzmof '$RemoteArchive' -C '$RemoteData' && rm -f '$RemoteArchive'"
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to extract Barony data on the Android target.'
    }
    & $Adb @AdbArguments shell "test -f '$RemoteData/$ManifestName' && test -f '$RemoteData/lang/en.txt' && test -f '$RemoteData/images/system/font8x8.png' && test -f '$RemoteData/maps/start.lmp' && test -f '$RemoteData/models/models.txt' && test -f '$RemoteData/sound/sounds.txt' && test -f '$RemoteData/music/mines00.ogg'"
    if ($LASTEXITCODE -ne 0) {
        throw 'Android data validation failed after extraction.'
    }

    Write-Host "Menu data deployed to $RemoteData ($($StagedFiles.Count) owned files, $StagedSize bytes before compression)."
    Write-Host "Deployment manifest: Barony v$ExpectedGameVersion / source $ExpectedSourceCommit."
    Write-Host "DLC entitlements: $($DlcEntitlements.Count)."
    Write-Host 'Holiday themes, tutorial videos, binaries, SDKs, and models.cache were not copied.'
}
finally {
    if (Test-Path -LiteralPath $StagingRoot) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force
    }
    $Archive = Join-Path $TemporaryBase 'barony-menu-data.tar.gz'
    if (Test-Path -LiteralPath $Archive) {
        Remove-Item -LiteralPath $Archive -Force
    }
}
