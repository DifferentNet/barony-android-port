[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ExpectedGameVersion = '5.0.2'
$ExpectedSourceCommit = '962a5ce36d10207beef7d8673876e0cebf8e76e4'
$ManifestName = '.barony-android-data.json'
$RequiredDirectories = @(
    'books', 'data', 'fonts', 'images', 'items',
    'lang', 'maps', 'models', 'music', 'sound'
)
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

function Get-BaronyInstallCandidates {
    $Candidates = [System.Collections.Generic.List[string]]::new()
    $Candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\Barony')

    $ProgramFilesX86 = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::ProgramFilesX86)
    $ProgramFiles = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::ProgramFiles)
    foreach ($Base in @($ProgramFilesX86, $ProgramFiles)) {
        if ($Base) {
            $Candidates.Add((Join-Path $Base 'GOG Galaxy\Games\Barony'))
        }
    }
    $Candidates.Add('C:\GOG Games\Barony')

    return @($Candidates | Select-Object -Unique)
}

function Test-LooksLikeBaronyInstall {
    param([Parameter(Mandatory)][string]$Path)

    return (Test-Path -LiteralPath (Join-Path $Path 'lang\en.txt') -PathType Leaf) `
        -and (Test-Path -LiteralPath (Join-Path $Path 'maps\start.lmp') -PathType Leaf) `
        -and (Test-Path -LiteralPath (Join-Path $Path 'models\models.txt') -PathType Leaf)
}

if (-not $SourcePath) {
    $Detected = @(
        Get-BaronyInstallCandidates |
            Where-Object { Test-LooksLikeBaronyInstall -Path $_ }
    )
    if ($Detected.Count -eq 0) {
        throw @'
No compatible Barony installation was found automatically.

Install Barony 5.0.2 through Steam or GOG, then run this script with:
  -SourcePath "C:\path\to\Barony"
'@
    }
    $SourcePath = $Detected[0]
    if ($Detected.Count -gt 1) {
        Write-Host "Multiple Barony installations were found; using: $SourcePath"
        Write-Host 'Pass -SourcePath to select another installation.'
    }
}

$SourcePath = [IO.Path]::GetFullPath($SourcePath)
if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    throw "Barony installation directory does not exist: $SourcePath"
}

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-Location) "Barony-Android-Data-$ExpectedGameVersion.zip"
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$OutputDirectory = Split-Path -Parent $OutputPath
$SourcePrefix = $SourcePath.TrimEnd('\') + '\'
if ($OutputPath.Equals(
        $SourcePath,
        [StringComparison]::OrdinalIgnoreCase) `
        -or $OutputPath.StartsWith(
            $SourcePrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The output archive must be outside the Barony installation directory.'
}
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    throw "Output already exists. Use -Force to replace it: $OutputPath"
}

$CriticalFiles = @($ExpectedCriticalHashes.Keys)
foreach ($RelativePath in $RequiredDirectories + $RequiredFiles + $CriticalFiles) {
    $Candidate = Join-Path $SourcePath $RelativePath
    if (-not (Test-Path -LiteralPath $Candidate)) {
        throw "Owned Barony data is incomplete; missing: $Candidate"
    }
}

$SourceCheckout = Join-Path $SourcePath '_barony-source'
if (Test-Path -LiteralPath (Join-Path $SourceCheckout '.git')) {
    $ActualSourceCommit = (& git.exe -C $SourceCheckout rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $ActualSourceCommit) {
        throw "Unable to read the installed Barony source revision from $SourceCheckout"
    }
    if ($ActualSourceCommit -ne $ExpectedSourceCommit) {
        throw "Unsupported Barony data version. Expected v$ExpectedGameVersion source " `
            + "$ExpectedSourceCommit, found $ActualSourceCommit."
    }
    Write-Host "Validated installed source commit $ActualSourceCommit."
}

$CriticalHashes = [ordered]@{}
foreach ($RelativePath in $CriticalFiles) {
    $ActualHash = (
        Get-FileHash -Algorithm SHA256 -LiteralPath (
            Join-Path $SourcePath $RelativePath)
    ).Hash.ToLowerInvariant()
    if ($ActualHash -ne $ExpectedCriticalHashes[$RelativePath]) {
        throw "Unsupported or modified Barony data file: $RelativePath. " `
            + "Expected data from Barony v$ExpectedGameVersion."
    }
    $CriticalHashes[$RelativePath] = $ActualHash
}
Write-Host "Validated owned Barony v$ExpectedGameVersion data."

$FilesByRelativePath = [ordered]@{}
foreach ($Directory in $RequiredDirectories) {
    $DirectoryPath = Join-Path $SourcePath $Directory
    $DirectoryItem = Get-Item -LiteralPath $DirectoryPath -Force
    if (($DirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Symbolic links and reparse points are not supported: $DirectoryPath"
    }
    $DirectoryEntries = @(
        Get-ChildItem -LiteralPath $DirectoryPath -Recurse -Force
    )
    foreach ($Entry in $DirectoryEntries) {
        if (($Entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Symbolic links and reparse points are not supported: $($Entry.FullName)"
        }
    }
    foreach ($File in $DirectoryEntries | Where-Object { -not $_.PSIsContainer }) {
        if (-not $File.FullName.StartsWith(
                $SourcePrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Owned data resolved outside the Barony installation: $($File.FullName)"
        }
        $RelativePath = $File.FullName.Substring($SourcePrefix.Length).Replace('\', '/')
        $LowerPath = $RelativePath.ToLowerInvariant()
        if ($LowerPath.EndsWith('.ogv') -or $LowerPath.EndsWith('/models.cache')) {
            continue
        }
        $FilesByRelativePath[$RelativePath] = $File
    }
}
foreach ($FileName in $RequiredFiles) {
    $FilesByRelativePath[$FileName] = Get-Item -LiteralPath (
        Join-Path $SourcePath $FileName)
}

$SortedRelativePaths = @($FilesByRelativePath.Keys | Sort-Object)
$UncompressedBytes = [long]0
foreach ($RelativePath in $SortedRelativePaths) {
    $UncompressedBytes += $FilesByRelativePath[$RelativePath].Length
}

$SourceType = if ($SourcePath -match '(?i)steamapps[\\/]common') {
    'steam'
}
elseif ($SourcePath -match '(?i)gog') {
    'gog'
}
else {
    'custom'
}

$Manifest = [ordered]@{
    schemaVersion = 1
    gameVersion = $ExpectedGameVersion
    sourceCommit = $ExpectedSourceCommit
    deployedAtUtc = [DateTime]::UtcNow.ToString('o')
    deploymentMethod = 'windows-archive-builder-v2'
    sourceType = $SourceType
    fileCount = $SortedRelativePaths.Count
    uncompressedBytes = $UncompressedBytes
    criticalFiles = $CriticalHashes
}
$ManifestBytes = [Text.Encoding]::UTF8.GetBytes(
    ($Manifest | ConvertTo-Json -Depth 4))

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$PartialPath = "$OutputPath.partial"
if (Test-Path -LiteralPath $PartialPath) {
    Remove-Item -LiteralPath $PartialPath -Force
}
if ((Test-Path -LiteralPath $OutputPath) -and $Force) {
    Remove-Item -LiteralPath $OutputPath -Force
}

$ArchiveStream = $null
$Archive = $null
try {
    $ArchiveStream = [IO.File]::Open(
        $PartialPath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None)
    $Archive = [IO.Compression.ZipArchive]::new(
        $ArchiveStream,
        [IO.Compression.ZipArchiveMode]::Create,
        $true)

    $ManifestEntry = $Archive.CreateEntry(
        $ManifestName,
        [IO.Compression.CompressionLevel]::Optimal)
    $ManifestStream = $ManifestEntry.Open()
    try {
        $ManifestStream.Write($ManifestBytes, 0, $ManifestBytes.Length)
    }
    finally {
        $ManifestStream.Dispose()
    }

    $Index = 0
    foreach ($RelativePath in $SortedRelativePaths) {
        $SourceFile = $FilesByRelativePath[$RelativePath]
        $Entry = $Archive.CreateEntry(
            $RelativePath,
            [IO.Compression.CompressionLevel]::Optimal)
        $Entry.LastWriteTime = $SourceFile.LastWriteTimeUtc
        $EntryStream = $Entry.Open()
        $InputStream = [IO.File]::OpenRead($SourceFile.FullName)
        try {
            $InputStream.CopyTo($EntryStream)
        }
        finally {
            $InputStream.Dispose()
            $EntryStream.Dispose()
        }
        $Index++
        if (($Index % 250) -eq 0 -or $Index -eq $SortedRelativePaths.Count) {
            Write-Progress `
                -Activity 'Creating Barony Android owned-data archive' `
                -Status "$Index / $($SortedRelativePaths.Count) files" `
                -PercentComplete (($Index * 100) / $SortedRelativePaths.Count)
        }
    }
}
finally {
    Write-Progress -Activity 'Creating Barony Android owned-data archive' -Completed
    if ($Archive) {
        $Archive.Dispose()
    }
    if ($ArchiveStream) {
        $ArchiveStream.Dispose()
    }
}

try {
    $VerifyStream = [IO.File]::OpenRead($PartialPath)
    $VerifyArchive = [IO.Compression.ZipArchive]::new(
        $VerifyStream,
        [IO.Compression.ZipArchiveMode]::Read,
        $false)
    try {
        if ($VerifyArchive.Entries.Count -ne ($SortedRelativePaths.Count + 1)) {
            throw "Archive file count mismatch after creation."
        }
        if (-not $VerifyArchive.GetEntry($ManifestName)) {
            throw "Archive manifest is missing after creation."
        }
        foreach ($RelativePath in $CriticalFiles) {
            $Entry = $VerifyArchive.GetEntry($RelativePath.Replace('\', '/'))
            if (-not $Entry) {
                throw "Archive critical file is missing: $RelativePath"
            }
            $EntryStream = $Entry.Open()
            $Hasher = [Security.Cryptography.SHA256]::Create()
            try {
                $EntryHash = -join (
                    $Hasher.ComputeHash($EntryStream) |
                        ForEach-Object { $_.ToString('x2') }
                )
            }
            finally {
                $Hasher.Dispose()
                $EntryStream.Dispose()
            }
            if ($EntryHash -ne $ExpectedCriticalHashes[$RelativePath]) {
                throw "Archive verification failed for: $RelativePath"
            }
        }
    }
    finally {
        $VerifyArchive.Dispose()
        $VerifyStream.Dispose()
    }

    Move-Item -LiteralPath $PartialPath -Destination $OutputPath -Force
}
catch {
    if (Test-Path -LiteralPath $PartialPath) {
        Remove-Item -LiteralPath $PartialPath -Force
    }
    throw
}

$ArchiveHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath
).Hash.ToLowerInvariant()
$SidecarPath = "$OutputPath.sha256"
[IO.File]::WriteAllText(
    $SidecarPath,
    "$ArchiveHash  $([IO.Path]::GetFileName($OutputPath))`n",
    (New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "Owned-data archive: $OutputPath"
Write-Host "SHA-256: $ArchiveHash"
Write-Host "Files: $($SortedRelativePaths.Count)"
Write-Host "Uncompressed data: $UncompressedBytes bytes"
Write-Host "Source type: $SourceType"
Write-Host ''
Write-Host 'Copy the ZIP to the Android device, start Barony Android Port,'
Write-Host 'and select Import archive. Do not extract the ZIP manually.'
Write-Host 'Commercial data remains outside the APK and public repository.'
