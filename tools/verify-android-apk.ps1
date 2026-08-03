[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ApkPath,

    [Parameter(Mandatory)]
    [ValidateSet('Smoke', 'Game')]
    [string]$Variant,

    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi = 'arm64-v8a'
)

$ErrorActionPreference = 'Stop'
$ApkPath = (Resolve-Path -LiteralPath $ApkPath).Path

function Find-AndroidSdk {
    $Candidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { $_ }

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $Candidate).Path
        }
    }

    throw 'Android SDK was not found.'
}

function Assert-ExactSet {
    param(
        [Parameter(Mandatory)]
        [string]$Label,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Actual,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Expected
    )

    $ActualSorted = @($Actual | Sort-Object -Unique)
    $ExpectedSorted = @($Expected | Sort-Object -Unique)
    $Difference = @(Compare-Object -ReferenceObject $ExpectedSorted -DifferenceObject $ActualSorted)
    if ($Difference.Count -gt 0) {
        $ActualText = if ($ActualSorted.Count) { $ActualSorted -join ', ' } else { '<none>' }
        $ExpectedText = if ($ExpectedSorted.Count) { $ExpectedSorted -join ', ' } else { '<none>' }
        throw "$Label mismatch. Expected: $ExpectedText. Actual: $ActualText."
    }
}

$AndroidSdk = Find-AndroidSdk
$Aapt2 = Join-Path $AndroidSdk 'build-tools\36.0.0\aapt2.exe'
if (-not (Test-Path -LiteralPath $Aapt2 -PathType Leaf)) {
    throw "Pinned Android Build Tools 36.0.0 were not found under $AndroidSdk."
}

$Badging = (& $Aapt2 dump badging $ApkPath 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "aapt2 failed to inspect $ApkPath.`n$Badging"
}
if ($Badging -notmatch "package: name='com\.zhdan\.baronyport'") {
    throw 'Unexpected or missing Android application ID.'
}
if ($Badging -notmatch "sdkVersion:'26'") {
    throw 'APK minimum SDK is not 26.'
}
if ($Badging -notmatch "targetSdkVersion:'36'") {
    throw 'APK target SDK is not 36.'
}
$RequestedPermissions = @(
    [Regex]::Matches(
        $Badging,
        "(?m)^uses-permission(?:-sdk-\d+)?: name='([^']+)'"
    ) | ForEach-Object { $_.Groups[1].Value }
)
$ExpectedPermissions = [string[]]@()
if ($Variant -eq 'Game') {
    $ExpectedPermissions = @('android.permission.INTERNET')
}
Assert-ExactSet `
    -Label 'Android permission set' `
    -Actual $RequestedPermissions `
    -Expected $ExpectedPermissions

Add-Type -AssemblyName System.IO.Compression
$Stream = [IO.File]::OpenRead($ApkPath)
try {
    $Archive = [IO.Compression.ZipArchive]::new(
        $Stream,
        [IO.Compression.ZipArchiveMode]::Read,
        $false
    )
    try {
        $EntryNames = @(
            $Archive.Entries |
                Where-Object { $_.Name } |
                ForEach-Object { $_.FullName.Replace('\', '/') }
        )

        $NativeEntries = @(
            $EntryNames |
                Where-Object { $_ -match '^lib/[^/]+/[^/]+\.so$' }
        )
        $ExpectedLibraries = if ($Variant -eq 'Game') {
            @(
                "lib/$Abi/libSDL2.so",
                "lib/$Abi/libbarony_game.so",
                "lib/$Abi/libc++_shared.so",
                "lib/$Abi/libmain.so",
                "lib/$Abi/libopenal.so"
            )
        }
        else {
            @(
                "lib/$Abi/libSDL2.so",
                "lib/$Abi/libc++_shared.so",
                "lib/$Abi/libmain.so"
            )
        }
        Assert-ExactSet -Label 'Native library set' -Actual $NativeEntries -Expected $ExpectedLibraries

        $AssetEntries = @($EntryNames | Where-Object { $_ -like 'assets/*' })
        [string[]]$ExpectedAssets = @()
        if ($Variant -eq 'Game') {
            $ExpectedAssets = @(
                'assets/licenses/Barony-and-bundled-components.txt',
                'assets/licenses/FreeType.txt',
                'assets/licenses/OpenAL-Soft.txt',
                'assets/licenses/PhysicsFS.txt',
                'assets/licenses/RapidJSON.txt',
                'assets/licenses/SDL2.txt',
                'assets/licenses/SDL2_image.txt',
                'assets/licenses/SDL2_net.txt',
                'assets/licenses/SDL2_ttf.txt',
                'assets/licenses/libogg.txt',
                'assets/licenses/libpng.txt',
                'assets/licenses/libvorbis.txt',
                'assets/licenses/zlib.txt'
            )
        }
        Assert-ExactSet -Label 'APK asset set' -Actual $AssetEntries -Expected $ExpectedAssets

        $ForbiddenPatterns = @(
            '(^|/)(books|data|fonts|images|items|lang|maps|models|music|sound)(/|$)',
            '(^|/)models\.cache$',
            '\.(key|dll|dylib)$'
        )
        foreach ($EntryName in $EntryNames) {
            foreach ($Pattern in $ForbiddenPatterns) {
                if ($EntryName -match $Pattern) {
                    throw "APK contains a forbidden commercial or proprietary path: $EntryName"
                }
            }
        }
    }
    finally {
        $Archive.Dispose()
    }
}
finally {
    $Stream.Dispose()
}

$Hash = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$Size = (Get-Item -LiteralPath $ApkPath).Length
Write-Host "Verified $Variant APK: $ApkPath"
Write-Host "ABI: $Abi"
Write-Host "Size: $Size bytes"
Write-Host "SHA-256: $Hash"
