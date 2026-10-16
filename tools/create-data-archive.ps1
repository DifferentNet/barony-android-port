[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$OutputPath,
    [switch]$IncludeHolidayThemes,
    [switch]$Mods,
    [string[]]$ModName,
    [switch]$NoWorkshopTitles,
    [switch]$Saves,
    [switch]$NoConfig,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

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
$RequiredDirectories = @(
    'books', 'data', 'fonts', 'images', 'items',
    'lang', 'maps', 'models', 'music', 'sound'
)
$HolidayThemeDirectories = @('themes/scarony', 'themes/merry')
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

$BaronyWorkshopAppId = '371970'
$ModManifestName = '.barony-android-mods.json'
$ModContentNames = @(
    'books', 'data', 'editor', 'fonts', 'images', 'items', 'lang',
    'maps', 'models', 'music', 'sound', 'preview.png'
)
$ModArchiveMaxFiles = 100000
$ModArchiveMaxBytes = [long]2 * 1024 * 1024 * 1024
$ModEntryMaxBytes = [long]256 * 1024 * 1024
$ModFolderNameMaxLength = 64

# Matches the Android save importer (Data & Saves > Import saves and settings).
$StateArchivePackageName = 'com.zhdan.baronyport'
$StateArchiveMaxFiles = 512
$StateArchiveMaxBytes = [long]64 * 1024 * 1024
$StateSkippedFileNames = @('steam_autocloud.vdf')

function Test-LooksLikeBaronyMod {
    param([Parameter(Mandatory)][string]$Path)

    foreach ($Child in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        if ($ModContentNames -contains $Child.Name.ToLowerInvariant()) {
            return $true
        }
    }
    return $false
}

# Matches the Android importer: Barony lists mods by folder name.
function ConvertTo-ModFolderName {
    param([Parameter(Mandatory)][string]$Name)

    $Clean = [regex]::Replace($Name, '[^A-Za-z0-9 _\-\.\(\)]', '_')
    $Clean = [regex]::Replace($Clean, '_{2,}', '_').Trim()
    $Clean = $Clean.TrimStart('.')
    $Clean = [regex]::Replace($Clean, '[ \.]+$', '')
    if ($Clean.Length -gt $ModFolderNameMaxLength) {
        $Clean = $Clean.Substring(0, $ModFolderNameMaxLength).Trim()
    }
    if (-not $Clean) {
        return 'Mod'
    }
    return $Clean
}

function Get-WorkshopTitles {
    param([string[]]$Ids)

    $Titles = @{}
    if (-not $Ids -or $Ids.Count -eq 0) {
        return $Titles
    }
    # Steam's public endpoint needs no account or key; only the item IDs are sent.
    $Body = @{ itemcount = $Ids.Count }
    for ($Index = 0; $Index -lt $Ids.Count; $Index++) {
        $Body["publishedfileids[$Index]"] = $Ids[$Index]
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $Response = Invoke-RestMethod `
            -Method Post `
            -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' `
            -Body $Body `
            -TimeoutSec 20 `
            -UseBasicParsing
        foreach ($Item in @($Response.response.publishedfiledetails)) {
            $TitleProperty = $Item.PSObject.Properties['title']
            if ($TitleProperty -and $TitleProperty.Value) {
                $Titles[[string]$Item.publishedfileid] = [string]$TitleProperty.Value
            }
        }
    }
    catch {
        Write-Warning ("Could not look up Steam Workshop titles: $($_.Exception.Message) " +
            'Workshop mods will be named by their Workshop ID.')
    }
    return $Titles
}

function New-BaronyModArchive {
    param(
        [Parameter(Mandatory)][string]$InstallPath,
        [Parameter(Mandatory)][string]$ArchivePath,
        [string[]]$NamePatterns,
        [switch]$SkipTitleLookup
    )

    # "powershell -File" passes -ModName 'A','B' as the single string "A,B".
    $NamePatterns = @(
        $NamePatterns |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )

    $Candidates = [System.Collections.Generic.List[object]]::new()
    $LocalModsPath = Join-Path $InstallPath 'mods'
    if (Test-Path -LiteralPath $LocalModsPath -PathType Container) {
        foreach ($Directory in @(Get-ChildItem -LiteralPath $LocalModsPath -Directory -Force)) {
            $Candidates.Add([pscustomobject]@{
                Path = $Directory.FullName
                Source = 'local'
                WorkshopId = ''
                Title = $Directory.Name
            })
        }
    }

    $WorkshopRoots = [System.Collections.Generic.List[string]]::new()
    if ($InstallPath -match '(?i)[\\/]steamapps[\\/]common[\\/]') {
        $WorkshopRoots.Add([IO.Path]::GetFullPath((Join-Path $InstallPath (
            "..\..\workshop\content\$BaronyWorkshopAppId"))))
    }
    foreach ($SteamRoot in @(Get-SteamRootCandidates -InstallPath $InstallPath)) {
        $WorkshopRoots.Add((Join-Path $SteamRoot "steamapps\workshop\content\$BaronyWorkshopAppId"))
    }
    $WorkshopIds = [System.Collections.Generic.List[string]]::new()
    foreach ($WorkshopRoot in @($WorkshopRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $WorkshopRoot -PathType Container)) {
            continue
        }
        foreach ($Directory in @(Get-ChildItem -LiteralPath $WorkshopRoot -Directory -Force)) {
            if ($Directory.Name -notmatch '^\d+$' -or $WorkshopIds.Contains($Directory.Name)) {
                continue
            }
            $WorkshopIds.Add($Directory.Name)
            $Candidates.Add([pscustomobject]@{
                Path = $Directory.FullName
                Source = 'workshop'
                WorkshopId = $Directory.Name
                Title = $Directory.Name
            })
        }
    }

    if ($WorkshopIds.Count -gt 0 -and -not $SkipTitleLookup) {
        $Titles = Get-WorkshopTitles -Ids @($WorkshopIds)
        foreach ($Candidate in $Candidates) {
            if ($Candidate.WorkshopId -and $Titles.ContainsKey($Candidate.WorkshopId)) {
                $Candidate.Title = $Titles[$Candidate.WorkshopId]
            }
        }
    }

    $Selected = [System.Collections.Generic.List[object]]::new()
    foreach ($Candidate in $Candidates) {
        if ($NamePatterns -and $NamePatterns.Count -gt 0) {
            $Matched = $false
            foreach ($Pattern in $NamePatterns) {
                if ($Candidate.Title -like $Pattern -or $Candidate.WorkshopId -like $Pattern `
                        -or (Split-Path -Leaf $Candidate.Path) -like $Pattern) {
                    $Matched = $true
                }
            }
            if (-not $Matched) {
                continue
            }
        }
        $Item = Get-Item -LiteralPath $Candidate.Path -Force
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Warning "Skipping a linked folder: $($Candidate.Path)"
            continue
        }
        if (-not (Test-LooksLikeBaronyMod -Path $Candidate.Path)) {
            Write-Warning "Skipping a folder that doesn't look like a Barony mod: $($Candidate.Path)"
            continue
        }
        $Selected.Add($Candidate)
    }
    if ($Selected.Count -eq 0) {
        throw ('No Barony mods were found. Subscribe to mods in the Steam Workshop or put ' +
            "them in $LocalModsPath, or check the -ModName filter.")
    }

    $UsedNames = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $Entries = [System.Collections.Generic.List[object]]::new()
    $ManifestMods = [System.Collections.Generic.List[object]]::new()
    $TotalBytes = [long]0
    foreach ($Mod in $Selected) {
        $Folder = ConvertTo-ModFolderName -Name $Mod.Title
        if (-not $UsedNames.Add($Folder)) {
            $Suffix = if ($Mod.WorkshopId) { $Mod.WorkshopId } else { '2' }
            $Folder = ConvertTo-ModFolderName -Name "$Folder ($Suffix)"
            $Counter = 3
            while (-not $UsedNames.Add($Folder)) {
                $Folder = ConvertTo-ModFolderName -Name "$($Mod.Title) ($Counter)"
                $Counter++
            }
        }
        $ModPrefix = $Mod.Path.TrimEnd('\') + '\'
        foreach ($File in @(Get-ChildItem -LiteralPath $Mod.Path -Recurse -File -Force)) {
            if (($File.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Symbolic links and reparse points are not supported: $($File.FullName)"
            }
            $Relative = $File.FullName.Substring($ModPrefix.Length).Replace('\', '/')
            $Lower = $Relative.ToLowerInvariant()
            if ($Lower -eq 'models.cache' -or $Lower.EndsWith('/models.cache')) {
                continue
            }
            if ($File.Length -gt $ModEntryMaxBytes) {
                throw "A mod file is larger than the Android importer accepts (256 MB): $($File.FullName)"
            }
            $TotalBytes += $File.Length
            $Entries.Add([pscustomobject]@{ Name = "$Folder/$Relative"; File = $File })
        }
        $ManifestMods.Add([ordered]@{
            folder = $Folder
            title = $Mod.Title
            source = $Mod.Source
            workshopId = $Mod.WorkshopId
        })
        $Label = if ($Mod.Source -eq 'workshop') { "Workshop $($Mod.WorkshopId)" } else { 'local mod' }
        Write-Host "Including mod: $Folder ($Label)"
    }
    if ($Entries.Count -gt $ModArchiveMaxFiles) {
        throw "The selected mods contain more than $ModArchiveMaxFiles files."
    }
    if ($TotalBytes -gt $ModArchiveMaxBytes) {
        throw 'The selected mods are larger than 2 GB. Use -ModName to pick fewer mods.'
    }

    $Manifest = [ordered]@{
        schemaVersion = 1
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        builder = 'windows-archive-builder-v3'
        mods = @($ManifestMods)
    }
    $ManifestBytes = [Text.Encoding]::UTF8.GetBytes(($Manifest | ConvertTo-Json -Depth 4))

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $PartialPath = "$ArchivePath.partial"
    if (Test-Path -LiteralPath $PartialPath) {
        Remove-Item -LiteralPath $PartialPath -Force
    }
    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }
    $ArchiveStream = $null
    $Archive = $null
    try {
        $ArchiveStream = [IO.File]::Open(
            $PartialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $Archive = [IO.Compression.ZipArchive]::new(
            $ArchiveStream, [IO.Compression.ZipArchiveMode]::Create, $true)
        $ManifestEntry = $Archive.CreateEntry($ModManifestName, [IO.Compression.CompressionLevel]::Optimal)
        $ManifestStream = $ManifestEntry.Open()
        try {
            $ManifestStream.Write($ManifestBytes, 0, $ManifestBytes.Length)
        }
        finally {
            $ManifestStream.Dispose()
        }
        $Index = 0
        foreach ($Item in $Entries) {
            $Entry = $Archive.CreateEntry($Item.Name, [IO.Compression.CompressionLevel]::Optimal)
            $Entry.LastWriteTime = $Item.File.LastWriteTimeUtc
            $EntryStream = $Entry.Open()
            $InputStream = [IO.File]::OpenRead($Item.File.FullName)
            try {
                $InputStream.CopyTo($EntryStream)
            }
            finally {
                $InputStream.Dispose()
                $EntryStream.Dispose()
            }
            $Index++
            if (($Index % 250) -eq 0 -or $Index -eq $Entries.Count) {
                Write-Progress -Activity 'Creating Barony Android mod archive' `
                    -Status "$Index / $($Entries.Count) files" `
                    -PercentComplete (($Index * 100) / $Entries.Count)
            }
        }
    }
    finally {
        Write-Progress -Activity 'Creating Barony Android mod archive' -Completed
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
            $VerifyStream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            if ($VerifyArchive.Entries.Count -ne ($Entries.Count + 1)) {
                throw 'Mod archive file count mismatch after creation.'
            }
            if (-not $VerifyArchive.GetEntry($ModManifestName)) {
                throw 'Mod archive manifest is missing after creation.'
            }
        }
        finally {
            $VerifyArchive.Dispose()
            $VerifyStream.Dispose()
        }
        Move-Item -LiteralPath $PartialPath -Destination $ArchivePath -Force
    }
    catch {
        if (Test-Path -LiteralPath $PartialPath) {
            Remove-Item -LiteralPath $PartialPath -Force
        }
        throw
    }

    $ArchiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        "$ArchivePath.sha256",
        "$ArchiveHash  $([IO.Path]::GetFileName($ArchivePath))`n",
        (New-Object Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host "Mod archive: $ArchivePath"
    Write-Host "SHA-256: $ArchiveHash"
    Write-Host "Mods: $($ManifestMods.Count)"
    Write-Host "Files: $($Entries.Count)"
    Write-Host "Uncompressed data: $TotalBytes bytes"
    Write-Host ''
    Write-Host 'Copy the ZIP to the Android device, open Data & Saves on the main menu,'
    Write-Host 'and choose Import mods. Mods belong to their authors; do not share this ZIP.'
}

function New-BaronySaveArchive {
    param(
        [Parameter(Mandatory)][string]$InstallPath,
        [Parameter(Mandatory)][string]$ArchivePath,
        [switch]$SkipConfig
    )

    # On Windows, Barony keeps saves and settings next to the game.
    $Folders = @('savegames')
    if (-not $SkipConfig) {
        $Folders += 'config'
    }
    $Entries = [System.Collections.Generic.List[object]]::new()
    $TotalBytes = [long]0
    foreach ($Folder in $Folders) {
        $FolderPath = Join-Path $InstallPath $Folder
        if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
            continue
        }
        $FolderPrefix = $FolderPath.TrimEnd('\') + '\'
        foreach ($File in @(Get-ChildItem -LiteralPath $FolderPath -Recurse -File -Force)) {
            if (($File.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Symbolic links and reparse points are not supported: $($File.FullName)"
            }
            if ($StateSkippedFileNames -contains $File.Name) {
                continue
            }
            $Relative = $File.FullName.Substring($FolderPrefix.Length).Replace('\', '/')
            $TotalBytes += $File.Length
            $Entries.Add([pscustomobject]@{ Name = "$Folder/$Relative"; File = $File })
        }
    }
    if (-not ($Entries | Where-Object { $_.Name.StartsWith('savegames/') })) {
        throw "No Barony saves were found in $(Join-Path $InstallPath 'savegames')."
    }
    if ($Entries.Count -gt $StateArchiveMaxFiles) {
        throw "The saves contain more than $StateArchiveMaxFiles files, which the Android importer rejects."
    }
    if ($TotalBytes -gt $StateArchiveMaxBytes) {
        throw 'The saves are larger than 64 MB, which the Android importer rejects.'
    }

    $Hashes = [ordered]@{}
    foreach ($Item in $Entries) {
        $Hashes[$Item.Name] = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $Item.File.FullName
        ).Hash.ToLowerInvariant()
    }
    $Manifest = [ordered]@{
        schemaVersion = 1
        packageName = $StateArchivePackageName
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        builder = 'windows-archive-builder-v3'
        files = $Hashes
    }
    $ManifestBytes = [Text.Encoding]::UTF8.GetBytes(($Manifest | ConvertTo-Json -Depth 4))

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $PartialPath = "$ArchivePath.partial"
    if (Test-Path -LiteralPath $PartialPath) {
        Remove-Item -LiteralPath $PartialPath -Force
    }
    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }
    $ArchiveStream = $null
    $Archive = $null
    try {
        $ArchiveStream = [IO.File]::Open(
            $PartialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $Archive = [IO.Compression.ZipArchive]::new(
            $ArchiveStream, [IO.Compression.ZipArchiveMode]::Create, $true)
        $ManifestEntry = $Archive.CreateEntry('manifest.json', [IO.Compression.CompressionLevel]::Optimal)
        $ManifestStream = $ManifestEntry.Open()
        try {
            $ManifestStream.Write($ManifestBytes, 0, $ManifestBytes.Length)
        }
        finally {
            $ManifestStream.Dispose()
        }
        foreach ($Item in $Entries) {
            $Entry = $Archive.CreateEntry("payload/$($Item.Name)", [IO.Compression.CompressionLevel]::Optimal)
            $Entry.LastWriteTime = $Item.File.LastWriteTimeUtc
            $EntryStream = $Entry.Open()
            $InputStream = [IO.File]::OpenRead($Item.File.FullName)
            try {
                $InputStream.CopyTo($EntryStream)
            }
            finally {
                $InputStream.Dispose()
                $EntryStream.Dispose()
            }
        }
    }
    finally {
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
            $VerifyStream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            if ($VerifyArchive.Entries.Count -ne ($Entries.Count + 1)) {
                throw 'Save archive file count mismatch after creation.'
            }
            if (-not $VerifyArchive.GetEntry('manifest.json')) {
                throw 'Save archive manifest is missing after creation.'
            }
        }
        finally {
            $VerifyArchive.Dispose()
            $VerifyStream.Dispose()
        }
        Move-Item -LiteralPath $PartialPath -Destination $ArchivePath -Force
    }
    catch {
        if (Test-Path -LiteralPath $PartialPath) {
            Remove-Item -LiteralPath $PartialPath -Force
        }
        throw
    }

    $ArchiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        "$ArchivePath.sha256",
        "$ArchiveHash  $([IO.Path]::GetFileName($ArchivePath))`n",
        (New-Object Text.UTF8Encoding($false)))

    $SaveCount = @($Entries | Where-Object { $_.Name -like 'savegames/*.baronysave' }).Count
    Write-Host ''
    Write-Host "Save archive: $ArchivePath"
    Write-Host "SHA-256: $ArchiveHash"
    Write-Host "Save games: $SaveCount"
    Write-Host "Files: $($Entries.Count)"
    if ($SkipConfig) {
        Write-Host 'Settings: not included (-NoConfig).'
    }
    Write-Host ''
    Write-Host 'Copy the ZIP to the Android device, open Data & Saves on the main menu,'
    Write-Host 'and choose Import saves and settings (on a TV: Receive from PC).'
    Write-Host 'Saves with the same names on the device are replaced.'
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
$SourceType = if ($SourcePath -match '(?i)steamapps[\\/]common') {
    'steam'
}
elseif ($SourcePath -match '(?i)gog') {
    'gog'
}
else {
    'custom'
}

if ($Mods -and $Saves) {
    throw 'Use -Mods and -Saves in separate runs; each creates its own ZIP.'
}
if ($NoConfig -and -not $Saves) {
    throw '-NoConfig works only together with -Saves.'
}

if ($Saves) {
    if (-not $OutputPath) {
        $OutputPath = Join-Path (Get-Location) 'Barony-Android-Saves-from-PC.zip'
    }
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "Output already exists. Use -Force to replace it: $OutputPath"
    }
    $SaveOutputDirectory = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $SaveOutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $SaveOutputDirectory -Force | Out-Null
    }
    New-BaronySaveArchive `
        -InstallPath $SourcePath `
        -ArchivePath $OutputPath `
        -SkipConfig:$NoConfig
    return
}

if ($Mods) {
    if (-not $OutputPath) {
        $OutputPath = Join-Path (Get-Location) 'Barony-Android-Mods.zip'
    }
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "Output already exists. Use -Force to replace it: $OutputPath"
    }
    $ModOutputDirectory = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $ModOutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $ModOutputDirectory -Force | Out-Null
    }
    New-BaronyModArchive `
        -InstallPath $SourcePath `
        -ArchivePath $OutputPath `
        -NamePatterns $ModName `
        -SkipTitleLookup:$NoWorkshopTitles
    return
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

$ArchiveDirectories = @($RequiredDirectories)
if ($IncludeHolidayThemes) {
    $ThemesPath = Join-Path $SourcePath 'themes'
    if (Test-Path -LiteralPath $ThemesPath -PathType Container) {
        $ThemesItem = Get-Item -LiteralPath $ThemesPath -Force
        if (($ThemesItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Symbolic links and reparse points are not supported: $ThemesPath"
        }
    }
    foreach ($Directory in $HolidayThemeDirectories) {
        if (Test-Path -LiteralPath (Join-Path $SourcePath $Directory) -PathType Container) {
            $ArchiveDirectories += $Directory
            Write-Host "Including holiday theme: $Directory"
        }
        else {
            Write-Warning "Holiday theme not found in the installation: $Directory"
        }
    }
}

$FilesByRelativePath = [ordered]@{}
foreach ($Directory in $ArchiveDirectories) {
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
        $FilesByRelativePath[$Dlc.KeyFile] = $KeyFile
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

$GeneratedFilesByRelativePath = [ordered]@{}
if ($SteamUnlockedPacks.Count -gt 0) {
    $UnlockLines = @(
        '# Barony Android DLC entitlements detected from cached Steam app tickets.'
        'format=1'
    ) + @($SteamUnlockedPacks)
    $GeneratedFilesByRelativePath[$DlcUnlockName] = [Text.Encoding]::UTF8.GetBytes(
        (($UnlockLines -join "`n") + "`n"))
}

$SortedRelativePaths = @($FilesByRelativePath.Keys | Sort-Object)
$UncompressedBytes = [long]0
foreach ($RelativePath in $SortedRelativePaths) {
    $UncompressedBytes += $FilesByRelativePath[$RelativePath].Length
}
foreach ($GeneratedBytes in $GeneratedFilesByRelativePath.Values) {
    $UncompressedBytes += $GeneratedBytes.Length
}
$PayloadFileCount = $SortedRelativePaths.Count + $GeneratedFilesByRelativePath.Count

$Manifest = [ordered]@{
    schemaVersion = 1
    gameVersion = $ExpectedGameVersion
    sourceCommit = $ExpectedSourceCommit
    deployedAtUtc = [DateTime]::UtcNow.ToString('o')
    deploymentMethod = 'windows-archive-builder-v3'
    sourceType = $SourceType
    fileCount = $PayloadFileCount
    uncompressedBytes = $UncompressedBytes
    criticalFiles = $CriticalHashes
    dlcEntitlements = @($DlcEntitlements)
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

    foreach ($RelativePath in $GeneratedFilesByRelativePath.Keys) {
        $Entry = $Archive.CreateEntry(
            $RelativePath,
            [IO.Compression.CompressionLevel]::Optimal)
        $EntryStream = $Entry.Open()
        try {
            $GeneratedBytes = $GeneratedFilesByRelativePath[$RelativePath]
            $EntryStream.Write($GeneratedBytes, 0, $GeneratedBytes.Length)
        }
        finally {
            $EntryStream.Dispose()
        }
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
        if ($VerifyArchive.Entries.Count -ne ($PayloadFileCount + 1)) {
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
        foreach ($RelativePath in $GeneratedFilesByRelativePath.Keys) {
            if (-not $VerifyArchive.GetEntry($RelativePath)) {
                throw "Archive generated file is missing: $RelativePath"
            }
        }
        foreach ($Dlc in $DlcDefinitions) {
            $KeyPath = Join-Path $SourcePath $Dlc.KeyFile
            if ((Test-Path -LiteralPath $KeyPath -PathType Leaf) `
                    -and -not $VerifyArchive.GetEntry($Dlc.KeyFile)) {
                throw "Archive DLC key file is missing: $($Dlc.KeyFile)"
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
Write-Host "Files: $PayloadFileCount"
Write-Host "Uncompressed data: $UncompressedBytes bytes"
Write-Host "Source type: $SourceType"
if (-not $IncludeHolidayThemes) {
    Write-Host 'Holiday themes: not included (use -IncludeHolidayThemes to add them).'
}
Write-Host ''
Write-Host 'Copy the ZIP to the Android device, start Barony Android Port,'
Write-Host 'and select Import archive. Do not extract the ZIP manually.'
Write-Host 'Commercial data remains outside the APK and public repository.'
