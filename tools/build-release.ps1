[CmdletBinding()]
param(
    [switch]$Clean,
    [Parameter(Mandatory)]
    [ValidateRange(1, 2100000000)]
    [int]$VersionCode,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Za-z._-]+$')]
    [string]$VersionName,
    [switch]$AllowDirtyWorktree
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$AndroidRoot = Join-Path $RepositoryRoot 'android'
$SigningPropertiesPath = Join-Path $AndroidRoot 'release-signing.properties'
$BuildScript = Join-Path $PSScriptRoot 'build-smoke.ps1'

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

$PortCommit = (& git -C $RepositoryRoot rev-parse HEAD 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $PortCommit) {
    throw 'Unable to determine the repository commit for the release build.'
}
$DirtyEntries = @(& git -C $RepositoryRoot status --porcelain 2>$null)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the release worktree.'
}
$DirtyWorktree = $DirtyEntries.Count -gt 0
if ($DirtyWorktree -and -not $AllowDirtyWorktree) {
    throw 'Refusing to build a release from a dirty worktree. Commit or stash the changes, or pass -AllowDirtyWorktree for a local-only test artifact.'
}
if ($DirtyWorktree) {
    Write-Warning 'Building a local-only release artifact from a dirty worktree.'
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

$AndroidSdk = Find-AndroidSdk
$BuildTools = Get-Item -LiteralPath (
    Join-Path $AndroidSdk 'build-tools\36.0.0'
) -ErrorAction SilentlyContinue
if (-not $BuildTools) {
    throw "Pinned Android Build Tools 36.0.0 were not found under $AndroidSdk."
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
$RequestedPermissions = @(
    [Regex]::Matches(
        $Badging,
        "(?m)^uses-permission(?:-sdk-\d+)?: name='([^']+)'"
    ) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
)
if ($RequestedPermissions.Count -ne 1 -or $RequestedPermissions[0] -ne 'android.permission.INTERNET') {
    $PermissionText = if ($RequestedPermissions.Count) {
        $RequestedPermissions -join ', '
    }
    else {
        '<none>'
    }
    throw "Release APK permission set mismatch. Expected only android.permission.INTERNET. Actual: $PermissionText."
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

$ArchiveBuilderSource = Join-Path $PSScriptRoot 'create-data-archive.ps1'
$ArchiveBuilderPath = Join-Path $AndroidRoot 'artifacts\Barony-Android-Data-Archive-Builder-5.0.2.ps1'
Copy-Item -LiteralPath $ArchiveBuilderSource -Destination $ArchiveBuilderPath -Force
$ArchiveBuilderHash = (
    Get-FileHash -LiteralPath $ArchiveBuilderPath -Algorithm SHA256
).Hash.ToLowerInvariant()
Set-Content `
    -LiteralPath "$ArchiveBuilderPath.sha256" `
    -Value "$ArchiveBuilderHash  $([IO.Path]::GetFileName($ArchiveBuilderPath))" `
    -Encoding ASCII

$JavaExecutable = if ($env:JAVA_HOME) {
    Join-Path $env:JAVA_HOME 'bin\java.exe'
}
else {
    $null
}
$JavaVersion = if ($JavaExecutable -and (Test-Path -LiteralPath $JavaExecutable)) {
    ((& $JavaExecutable --version 2>&1 | Select-Object -First 1) -join '').Trim()
}
else {
    '<unavailable>'
}
$WrapperPropertiesPath = Join-Path $AndroidRoot 'gradle\wrapper\gradle-wrapper.properties'
$WrapperPropertiesText = Get-Content -LiteralPath $WrapperPropertiesPath -Raw
$GradleVersion = if ($WrapperPropertiesText -match 'gradle-([0-9.]+)-bin\.zip') {
    $Matches[1]
}
else {
    '<unknown>'
}
$GradleChecksum = if ($WrapperPropertiesText -match 'distributionSha256Sum=([0-9a-fA-F]{64})') {
    $Matches[1].ToLowerInvariant()
}
else {
    '<unknown>'
}
$RootGradleText = Get-Content -LiteralPath (
    Join-Path $AndroidRoot 'build.gradle.kts'
) -Raw
$AgpVersion = if ($RootGradleText -match 'com\.android\.application"\) version "([^"]+)"') {
    $Matches[1]
}
else {
    '<unknown>'
}
$AppGradleText = Get-Content -LiteralPath (
    Join-Path $AndroidRoot 'app\build.gradle.kts'
) -Raw
$NdkVersion = if ($AppGradleText -match 'ndkVersion = "([^"]+)"') {
    $Matches[1]
}
else {
    '<unknown>'
}
$CmakeVersion = if ($AppGradleText -match '(?s)cmake\s*\{\s*path\s*=\s*file\("[^"]+"\)\s*version\s*=\s*"([0-9.]+)"') {
    $Matches[1]
}
else {
    '<unknown>'
}
$DependencyMetadata = [System.Collections.Generic.List[string]]::new()
$PinnedDependencyPaths = @(
    'external/SDL',
    'external/SDL_image',
    'external/SDL_image/external/libpng',
    'external/SDL_image/external/zlib',
    'external/SDL_net',
    'external/SDL_ttf',
    'external/SDL_ttf/external/freetype',
    'external/physfs',
    'external/rapidjson',
    'external/openal-soft',
    'external/ogg',
    'external/vorbis'
)
foreach ($DependencyPath in $PinnedDependencyPaths) {
    $AbsoluteDependencyPath = Join-Path $RepositoryRoot $DependencyPath
    $Revision = (
        & git -C $AbsoluteDependencyPath rev-parse HEAD 2>$null |
            Out-String
    ).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Revision) {
        throw "Unable to read release dependency revision: $DependencyPath"
    }
    $DependencyMetadata.Add("dependency.$DependencyPath=$Revision")
}

$BuildInfoPath = "$ReleaseApk.build.txt"
$BuildInfo = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    "artifact=$([IO.Path]::GetFileName($ReleaseApk))"
    "versionName=$VersionName"
    "versionCode=$VersionCode"
    'abi=arm64-v8a'
    "portCommit=$PortCommit"
    "dirtyWorktree=$($DirtyWorktree.ToString().ToLowerInvariant())"
    'baronySourceCommit=962a5ce36d10207beef7d8673876e0cebf8e76e4'
    "toolchain.java=$JavaVersion"
    "toolchain.gradle=$GradleVersion"
    "toolchain.gradleDistributionSha256=$GradleChecksum"
    "toolchain.androidGradlePlugin=$AgpVersion"
    'toolchain.compileSdk=36'
    'toolchain.buildTools=36.0.0'
    "toolchain.ndk=$NdkVersion"
    "toolchain.cmake=$CmakeVersion"
    "sha256=$Hash"
)) {
    $BuildInfo.Add($Line)
}
foreach ($Line in $DependencyMetadata) {
    $BuildInfo.Add($Line)
}
Set-Content -LiteralPath $BuildInfoPath -Value $BuildInfo -Encoding ASCII

$Apk = Get-Item -LiteralPath $ReleaseApk
Write-Host "Release APK: $($Apk.FullName) ($($Apk.Length) bytes)"
Write-Host "SHA-256: $Hash"
Write-Host "Build metadata: $BuildInfoPath"
Write-Host "Data installer: $DataInstallerPath"
Write-Host "Data archive builder: $ArchiveBuilderPath"
Write-Host 'Verified: package/version/SDK metadata, non-debuggable manifest with only android.permission.INTERNET, release signature, exact ARM64 native-library set, notice-only assets, and no commercial data paths.'
