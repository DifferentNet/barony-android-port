[CmdletBinding()]
param(
    [switch]$Clean,
    [ValidateRange(1, 2100000000)]
    [int]$VersionCode = 5000201,
    [ValidatePattern('^[0-9A-Za-z._-]+$')]
    [string]$VersionName = '5.0.2-android-beta1'
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$AndroidRoot = Join-Path $RepositoryRoot 'android'
$SigningPropertiesPath = Join-Path $AndroidRoot 'release-signing.properties'
$BuildScript = Join-Path $PSScriptRoot 'build-smoke.ps1'

function Read-SimpleProperties {
    param([Parameter(Mandatory)][string]$Path)

    $Properties = @{}
    foreach ($Line in Get-Content -LiteralPath $Path) {
        $Trimmed = $Line.Trim()
        if (-not $Trimmed -or $Trimmed.StartsWith('#')) {
            continue
        }
        $Parts = $Trimmed.Split('=', 2)
        if ($Parts.Count -eq 2) {
            $Properties[$Parts[0].Trim()] = $Parts[1].Trim()
        }
    }
    return $Properties
}

if (-not (Test-Path -LiteralPath $SigningPropertiesPath)) {
    throw 'Release signing is not configured. Run tools/create-release-keystore.ps1 first.'
}

$Signing = Read-SimpleProperties -Path $SigningPropertiesPath
foreach ($RequiredKey in @('storeFile', 'keyAlias')) {
    if (-not $Signing[$RequiredKey]) {
        throw "Signing metadata is missing '$RequiredKey'."
    }
}
if (-not (Test-Path -LiteralPath $Signing.storeFile)) {
    throw "Release keystore not found: $($Signing.storeFile)"
}

$Password = $env:BARONY_RELEASE_KEYSTORE_PASSWORD
if (-not $Password -and $Signing.passwordFile -and (Test-Path -LiteralPath $Signing.passwordFile)) {
    $Password = (Get-Content -LiteralPath $Signing.passwordFile -Raw).Trim()
}
if (-not $Password) {
    $SecurePassword = Read-Host 'Release keystore password' -AsSecureString
    $Password = [Net.NetworkCredential]::new('', $SecurePassword).Password
}
if (-not $Password) {
    throw 'A release keystore password is required.'
}

$PreviousPassword = $env:BARONY_RELEASE_KEYSTORE_PASSWORD
$env:BARONY_RELEASE_KEYSTORE_PASSWORD = $Password
try {
    & $BuildScript `
        -Clean:$Clean `
        -BuildGame `
        -Release `
        -SignedRelease `
        -VersionCode $VersionCode `
        -VersionName $VersionName
}
finally {
    $env:BARONY_RELEASE_KEYSTORE_PASSWORD = $PreviousPassword
    $Password = $null
}

$BuiltApk = Join-Path $AndroidRoot 'artifacts\app-release-barony-arm64-v8a.apk'
if (-not (Test-Path -LiteralPath $BuiltApk)) {
    throw "Release build did not produce the expected APK: $BuiltApk"
}

$SafeVersionName = $VersionName -replace '[^0-9A-Za-z._-]', '_'
$ReleaseApk = Join-Path $AndroidRoot "artifacts\Barony-Android-Port-$SafeVersionName-arm64-v8a.apk"
Copy-Item -LiteralPath $BuiltApk -Destination $ReleaseApk -Force

$AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$BuildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object Name -Match '^\d+\.\d+\.\d+$' |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $BuildTools) {
    throw 'Android SDK build-tools were not found.'
}
$ApkSigner = Join-Path $BuildTools.FullName 'apksigner.bat'
if (-not (Test-Path -LiteralPath $ApkSigner)) {
    throw "apksigner was not found: $ApkSigner"
}
$Aapt2 = Join-Path $BuildTools.FullName 'aapt2.exe'
if (-not (Test-Path -LiteralPath $Aapt2)) {
    throw "aapt2 was not found: $Aapt2"
}

& $ApkSigner verify --verbose --print-certs $ReleaseApk
if ($LASTEXITCODE -ne 0) {
    throw "APK signature verification failed with exit code $LASTEXITCODE."
}

$Badging = (& $Aapt2 dump badging $ReleaseApk | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect APK manifest metadata (exit code $LASTEXITCODE)."
}
$EscapedVersionName = [Regex]::Escape($VersionName)
if ($Badging -notmatch "package: name='com\.zhdan\.baronyport' versionCode='$VersionCode' versionName='$EscapedVersionName'") {
    throw 'Release APK package or version metadata does not match the requested release identity.'
}
if ($Badging -notmatch "sdkVersion:'26'" -or $Badging -notmatch "targetSdkVersion:'36'") {
    throw 'Release APK SDK metadata is not minSdk 26 / targetSdk 36.'
}
if ($Badging -notmatch "native-code: 'arm64-v8a'") {
    throw 'Release APK does not declare arm64-v8a as its native ABI.'
}
if ($Badging -match '(?m)^uses-permission:') {
    throw 'Release APK unexpectedly requests Android permissions.'
}
if ($Badging -match '(?m)^application-debuggable') {
    throw 'Release APK is unexpectedly debuggable.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$Archive = [IO.Compression.ZipFile]::OpenRead($ReleaseApk)
try {
    $Entries = @($Archive.Entries | ForEach-Object FullName)
}
finally {
    $Archive.Dispose()
}

$NativeEntries = @($Entries | Where-Object { $_ -like 'lib/*/*.so' })
$UnexpectedAbis = @($NativeEntries | Where-Object { $_ -notlike 'lib/arm64-v8a/*.so' })
if ($UnexpectedAbis) {
    throw "Release APK contains unexpected native ABIs: $($UnexpectedAbis -join ', ')"
}

$RequiredLibraries = @(
    'lib/arm64-v8a/libSDL2.so',
    'lib/arm64-v8a/libbarony_game.so',
    'lib/arm64-v8a/libc++_shared.so',
    'lib/arm64-v8a/libmain.so',
    'lib/arm64-v8a/libopenal.so'
)
foreach ($Library in $RequiredLibraries) {
    if ($Entries -notcontains $Library) {
        throw "Release APK is missing $Library."
    }
}
$UnexpectedLibraries = @($NativeEntries | Where-Object { $RequiredLibraries -notcontains $_ })
if ($UnexpectedLibraries) {
    throw "Release APK contains unexpected native libraries: $($UnexpectedLibraries -join ', ')"
}

$ForbiddenAssetPattern = '^assets/(books|data|fonts|images|items|lang|maps|models|music|sound)(/|$)'
$ForbiddenAssets = @($Entries | Where-Object { $_ -match $ForbiddenAssetPattern })
if ($ForbiddenAssets) {
    throw "Commercial game-data paths entered the release APK: $($ForbiddenAssets -join ', ')"
}
$UnexpectedAssets = @($Entries | Where-Object {
    $_ -like 'assets/*' -and $_ -notlike 'assets/licenses/*.txt'
})
if ($UnexpectedAssets) {
    throw "Release APK contains unexpected assets: $($UnexpectedAssets -join ', ')"
}

$RequiredNotices = @(
    'assets/licenses/Barony-and-bundled-components.txt',
    'assets/licenses/SDL2.txt',
    'assets/licenses/SDL2_image.txt',
    'assets/licenses/SDL2_net.txt',
    'assets/licenses/SDL2_ttf.txt',
    'assets/licenses/PhysicsFS.txt',
    'assets/licenses/RapidJSON.txt',
    'assets/licenses/OpenAL-Soft.txt',
    'assets/licenses/libogg.txt',
    'assets/licenses/libvorbis.txt',
    'assets/licenses/libpng.txt',
    'assets/licenses/zlib.txt',
    'assets/licenses/FreeType.txt'
)
foreach ($Notice in $RequiredNotices) {
    if ($Entries -notcontains $Notice) {
        throw "Release APK is missing open-source notice $Notice."
    }
}

$Hash = (Get-FileHash -LiteralPath $ReleaseApk -Algorithm SHA256).Hash.ToLowerInvariant()
$HashPath = "$ReleaseApk.sha256"
Set-Content -LiteralPath $HashPath -Value "$Hash  $([IO.Path]::GetFileName($ReleaseApk))" -Encoding ASCII

$DataInstallerSource = Join-Path $PSScriptRoot 'deploy-menu-data.ps1'
$DataInstallerPath = Join-Path $AndroidRoot 'artifacts\Barony-Android-Data-Installer-5.0.2.ps1'
Copy-Item -LiteralPath $DataInstallerSource -Destination $DataInstallerPath -Force
$DataInstallerHash = (Get-FileHash -LiteralPath $DataInstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content `
    -LiteralPath "$DataInstallerPath.sha256" `
    -Value "$DataInstallerHash  $([IO.Path]::GetFileName($DataInstallerPath))" `
    -Encoding ASCII

$PortCommit = (git -C $RepositoryRoot rev-parse HEAD).Trim()
$Dirty = if (git -C $RepositoryRoot status --porcelain) { 'true' } else { 'false' }
$BuildInfoPath = "$ReleaseApk.build.txt"
$BuildInfo = @(
    "artifact=$([IO.Path]::GetFileName($ReleaseApk))"
    "versionName=$VersionName"
    "versionCode=$VersionCode"
    'abi=arm64-v8a'
    "portCommit=$PortCommit"
    "dirtyWorktree=$Dirty"
    'baronySourceCommit=962a5ce36d10207beef7d8673876e0cebf8e76e4'
    "sha256=$Hash"
)
Set-Content -LiteralPath $BuildInfoPath -Value $BuildInfo -Encoding ASCII

$Apk = Get-Item -LiteralPath $ReleaseApk
Write-Host "Release APK: $($Apk.FullName) ($($Apk.Length) bytes)"
Write-Host "SHA-256: $Hash"
Write-Host "Build metadata: $BuildInfoPath"
Write-Host "Data installer: $DataInstallerPath"
Write-Host 'Verified: package/version/SDK metadata, non-debuggable and zero-permission manifest, release signature, exact ARM64 native-library set, notice-only assets, and no commercial data paths.'
