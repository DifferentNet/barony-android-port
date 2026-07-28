[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot

$ExpectedRevisions = [ordered]@{
    'external/SDL' = '5d249570393f7a37e037abf22cd6012a4cc56a71'
    'external/SDL_image' = 'c1bf2245b0ba63a25afe2f8574d305feca25af77'
    'external/SDL_image/external/libpng' = 'd5f3b730390cbbf9f1086a4aa97b7d44e42919ae'
    'external/SDL_image/external/zlib' = 'c4ea85eda90be5d47bb832108a520b4e82fe19c4'
    'external/SDL_net' = '669e75b84632e2c6cc5c65974ec9e28052cb7a4e'
    'external/SDL_ttf' = '2a891473eaf05ba1707a4b7913e6c4db7de7458a'
    'external/SDL_ttf/external/freetype' = '12c5e620858bd503731091e9371d06c0a3e7c967'
    'external/physfs' = 'eb3383b532c5f74bfeb42ec306ba2cf80eed988c'
    'external/rapidjson' = 'f54b0e47a08782a6131cc3d60f94d038fa6e0a51'
    'external/openal-soft' = 'b2c48f7718ef3fcf67921a8b6534c4914e328970'
    'external/ogg' = 'be05b13e98b048f0b5a0f5fa8ce514d56db5f822'
    'external/vorbis' = '0657aee69dec8508a0011f47f3b69d7538e9d262'
}

foreach ($Entry in $ExpectedRevisions.GetEnumerator()) {
    $DependencyPath = Join-Path $RepositoryRoot $Entry.Key
    if (-not (Test-Path -LiteralPath $DependencyPath -PathType Container)) {
        throw "Required dependency is not initialized: $($Entry.Key)"
    }

    $ActualRevision = (& git -C $DependencyPath rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $ActualRevision) {
        throw "Unable to read dependency revision: $($Entry.Key)"
    }
    if ($ActualRevision -ne $Entry.Value) {
        throw "Unexpected revision for $($Entry.Key): expected $($Entry.Value), found $ActualRevision"
    }

    Write-Host "Verified $($Entry.Key) at $ActualRevision"
}

Write-Host "Verified $($ExpectedRevisions.Count) pinned Android dependency revisions."
