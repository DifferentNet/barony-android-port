[CmdletBinding()]
param(
    [string]$KeystorePath = (Join-Path $env:USERPROFILE '.barony-android-port\barony-release.p12'),
    [string]$PasswordFile = (Join-Path $env:USERPROFILE '.barony-android-port\release-keystore.password'),
    [string]$KeyAlias = 'barony-android-port',
    [string]$DistinguishedName = 'CN=Barony Android Port Private Release,O=Private Build',
    [switch]$GeneratePasswordFile
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SigningPropertiesPath = Join-Path $RepositoryRoot 'android\release-signing.properties'

function Find-Jdk17 {
    $Candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:JAVA_HOME) {
        $Candidates.Add($env:JAVA_HOME)
    }

    $AdoptiumRoot = Join-Path $env:ProgramFiles 'Eclipse Adoptium'
    if (Test-Path -LiteralPath $AdoptiumRoot) {
        Get-ChildItem -LiteralPath $AdoptiumRoot -Directory -Filter 'jdk-17*' |
            Sort-Object Name -Descending |
            ForEach-Object { $Candidates.Add($_.FullName) }
    }

    foreach ($Candidate in $Candidates) {
        $Keytool = Join-Path $Candidate 'bin\keytool.exe'
        if (Test-Path -LiteralPath $Keytool) {
            return $Keytool
        }
    }

    throw 'JDK 17 keytool was not found. Install Eclipse Temurin 17 and retry.'
}

function New-RandomPassword {
    $Bytes = New-Object byte[] 32
    $Generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $Generator.GetBytes($Bytes)
    }
    finally {
        $Generator.Dispose()
    }
    return [Convert]::ToBase64String($Bytes)
}

function Protect-PasswordFile {
    param([Parameter(Mandatory)][string]$Path)

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $Acl = Get-Acl -LiteralPath $Path
    $Acl.SetAccessRuleProtection($true, $false)
    $Acl.SetAccessRule(
        [Security.AccessControl.FileSystemAccessRule]::new(
            $Identity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow
        )
    )
    Set-Acl -LiteralPath $Path -AclObject $Acl
}

if (Test-Path -LiteralPath $KeystorePath) {
    throw "Release keystore already exists: $KeystorePath"
}

$KeystoreDirectory = Split-Path -Parent $KeystorePath
$PasswordDirectory = Split-Path -Parent $PasswordFile
New-Item -ItemType Directory -Path $KeystoreDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $PasswordDirectory -Force | Out-Null

$Password = $env:BARONY_RELEASE_KEYSTORE_PASSWORD
if (-not $Password -and (Test-Path -LiteralPath $PasswordFile)) {
    $Password = (Get-Content -LiteralPath $PasswordFile -Raw).Trim()
}
if (-not $Password -and $GeneratePasswordFile) {
    $Password = New-RandomPassword
    Set-Content -LiteralPath $PasswordFile -Value $Password -NoNewline -Encoding ASCII
    Protect-PasswordFile -Path $PasswordFile
}
if (-not $Password) {
    $SecurePassword = Read-Host 'New release keystore password' -AsSecureString
    $Password = [Net.NetworkCredential]::new('', $SecurePassword).Password
}
if ($Password.Length -lt 12) {
    throw 'The release keystore password must contain at least 12 characters.'
}

$Keytool = Find-Jdk17
$PreviousPassword = $env:BARONY_RELEASE_KEYSTORE_PASSWORD
$env:BARONY_RELEASE_KEYSTORE_PASSWORD = $Password
try {
    & $Keytool -genkeypair `
        -keystore $KeystorePath `
        -storetype PKCS12 `
        -storepass:env BARONY_RELEASE_KEYSTORE_PASSWORD `
        -keypass:env BARONY_RELEASE_KEYSTORE_PASSWORD `
        -alias $KeyAlias `
        -keyalg RSA `
        -keysize 4096 `
        -sigalg SHA256withRSA `
        -validity 10000 `
        -dname $DistinguishedName
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed with exit code $LASTEXITCODE."
    }

    & $Keytool -list -v `
        -keystore $KeystorePath `
        -storepass:env BARONY_RELEASE_KEYSTORE_PASSWORD `
        -alias $KeyAlias |
        Select-String -Pattern 'Alias name:|Valid from:|SHA256:'
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the new keystore (exit code $LASTEXITCODE)."
    }
}
finally {
    $env:BARONY_RELEASE_KEYSTORE_PASSWORD = $PreviousPassword
    $Password = $null
}

$ResolvedKeystore = (Resolve-Path -LiteralPath $KeystorePath).Path.Replace('\', '/')
$ResolvedPasswordFile = if (Test-Path -LiteralPath $PasswordFile) {
    (Resolve-Path -LiteralPath $PasswordFile).Path.Replace('\', '/')
} else {
    ''
}
$SigningProperties = @(
    "storeFile=$ResolvedKeystore"
    "keyAlias=$KeyAlias"
    "passwordFile=$ResolvedPasswordFile"
)
Set-Content -LiteralPath $SigningPropertiesPath -Value $SigningProperties -Encoding ASCII

Write-Host "Release keystore: $ResolvedKeystore"
Write-Host "Ignored signing metadata: $SigningPropertiesPath"
if ($ResolvedPasswordFile) {
    Write-Host "Private password file: $ResolvedPasswordFile"
}
Write-Warning 'Back up the keystore and its password separately. Losing either prevents signing compatible updates.'
