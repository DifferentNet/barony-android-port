[CmdletBinding()]
param(
    [string]$SourcePath = 'C:\Program Files (x86)\Steam\steamapps\common\Barony',
    [string]$Serial
)

$ErrorActionPreference = 'Stop'

$ExpectedGameVersion = '5.0.2'
$ExpectedSourceCommit = '962a5ce36d10207beef7d8673876e0cebf8e76e4'
$ManifestName = '.barony-android-data.json'
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
        fileCount = $StagedFiles.Count
        uncompressedBytes = $StagedSize
        criticalFiles = $CriticalHashes
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
