[CmdletBinding()]
param(
    [string]$Serial,
    [string]$ApkPath,
    [ValidateRange(0, 1440)]
    [int]$DurationMinutes = 30,
    [ValidateRange(10, 300)]
    [int]$StartupTimeoutSeconds = 90,
    [string]$OutputDirectory,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$PackageName = 'com.zhdan.baronyport'
$LauncherComponent = 'com.zhdan.baronyport/.BaronyActivity'
$LogcatArguments = @(
    'logcat', '-d', '-v', 'threadtime',
    'BaronyAndroid:I',
    'BaronyTouch:I',
    'SDL/APP:V',
    'SDL:V',
    'AndroidRuntime:E',
    'ActivityManager:E',
    'libc:F',
    'DEBUG:F',
    '*:S'
)

$AndroidSdk = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
}
elseif ($env:ANDROID_HOME) {
    $env:ANDROID_HOME
}
else {
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

    $Devices = [System.Collections.Generic.List[string]]::new()
    foreach ($Line in $Lines) {
        if ($Line -match '^(.+?)\s+device(?:\s|$)') {
            $Devices.Add($Matches[1].Trim())
        }
    }
    return $Devices.ToArray()
}

$ConnectedDevices = @(Get-ConnectedDevices)
if ($Serial) {
    if ($ConnectedDevices -notcontains $Serial) {
        $Available = if ($ConnectedDevices.Count) { $ConnectedDevices -join ', ' } else { '(none)' }
        throw "ADB target '$Serial' is not connected. Available targets: $Available"
    }
    $TargetSerial = $Serial
}
elseif ($ConnectedDevices.Count -eq 1) {
    $TargetSerial = $ConnectedDevices[0]
}
elseif ($ConnectedDevices.Count -eq 0) {
    throw 'No usable Android device is connected.'
}
else {
    throw "More than one ADB target is connected. Pass -Serial with one of: $($ConnectedDevices -join ', ')"
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $PreviousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $Output = @(& $Adb -s $TargetSerial @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorPreference
    }
    if ($ExitCode -ne 0 -and -not $AllowFailure) {
        throw "ADB command failed (exit $ExitCode): adb -s $TargetSerial $($Arguments -join ' ')`n$($Output -join [Environment]::NewLine)"
    }
    return $Output
}

function Get-AppProcessId {
    $Output = @(Invoke-Adb -Arguments @('shell', 'pidof', $PackageName) -AllowFailure)
    foreach ($Line in $Output) {
        if ($Line -match '^\s*(\d+)') {
            return [int]$Matches[1]
        }
    }
    return $null
}

function Get-AudioUnderrunMaximum {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$AudioFlingerLines,
        [Parameter(Mandatory)]
        [int]$AppProcessId
    )

    $UnderrunColumn = -1
    $ReadingLocalLog = $false
    $Values = [System.Collections.Generic.List[long]]::new()
    foreach ($Line in $AudioFlingerLines) {
        if ($Line -match '^\s*Output thread ') {
            $ReadingLocalLog = $false
            $UnderrunColumn = -1
            continue
        }
        if ($Line -match '^\s*Local log:') {
            $ReadingLocalLog = $true
            continue
        }
        if ($ReadingLocalLog) {
            continue
        }
        if ($Line -match 'Client\(pid/uid\)' -and $Line -match 'Underruns') {
            $UnderrunColumn = $Line.IndexOf('Underruns')
            continue
        }

        if ($UnderrunColumn -lt 0 -or $Line -notmatch "(?<!\d)$AppProcessId/\s*\d+") {
            continue
        }

        $Tail = if ($Line.Length -gt $UnderrunColumn) {
            $Line.Substring($UnderrunColumn)
        }
        else {
            ''
        }
        if ($Tail -match '^\s*(\d+)\*?') {
            $Values.Add([long]$Matches[1])
        }
    }

    if ($Values.Count -eq 0) {
        return $null
    }
    return ($Values | Measure-Object -Maximum).Maximum
}

if (-not $ApkPath) {
    $ApkPath = Join-Path $RepositoryRoot 'android\artifacts\app-debug-barony-arm64-v8a.apk'
}
if (-not $SkipInstall) {
    if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
        throw "Barony APK was not found: $ApkPath. Build it with tools/build-barony.ps1 first."
    }
    $ApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
}

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SafeSerial = $TargetSerial -replace '[^A-Za-z0-9_.-]', '_'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepositoryRoot "android\test-results\$Timestamp-$SafeSerial"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$DeviceLines = [System.Collections.Generic.List[string]]::new()
$DeviceLines.Add("serial=$TargetSerial")
$DeviceLines.Add("model=$((Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.model')) -join '')")
$DeviceLines.Add("android_release=$((Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.release')) -join '')")
$DeviceLines.Add("sdk=$((Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.sdk')) -join '')")
$DeviceLines.Add("abi=$((Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.cpu.abi')) -join '')")
$DeviceLines | Set-Content -LiteralPath (Join-Path $OutputDirectory 'device.txt') -Encoding UTF8

Write-Host "ADB target: $TargetSerial"
Write-Host "Results: $OutputDirectory"

$PowerState = @(Invoke-Adb -Arguments @('shell', 'dumpsys', 'power')) -join [Environment]::NewLine
$WindowState = @(Invoke-Adb -Arguments @('shell', 'dumpsys', 'window')) -join [Environment]::NewLine
if ($PowerState -notmatch 'mWakefulness=Awake' -or $WindowState -match 'isKeyguardShowing=true') {
    throw 'The Android device is asleep or locked. Wake and unlock it before starting the physical-device test.'
}

if (-not $SkipInstall) {
    Write-Host "Installing: $ApkPath"
    $InstallOutput = @(Invoke-Adb -Arguments @('install', '-r', $ApkPath))
    $InstallOutput | ForEach-Object { Write-Host $_ }
}
else {
    Invoke-Adb -Arguments @('shell', 'pm', 'path', $PackageName) | Out-Null
    Write-Host 'Using the currently installed APK.'
}

Invoke-Adb -Arguments @('logcat', '-c') | Out-Null
Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $PackageName) | Out-Null
Write-Host "Launching: $LauncherComponent"
$LaunchOutput = @(Invoke-Adb -Arguments @('shell', 'am', 'start', '-W', '-n', $LauncherComponent))
$LaunchOutput | Set-Content -LiteralPath (Join-Path $OutputDirectory 'launch.txt') -Encoding UTF8
$PackageDetails = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'package', $PackageName
)) -join [Environment]::NewLine
$InstalledBuildIsDebuggable = $PackageDetails -match 'flags=\[[^\]]*DEBUGGABLE'

$RequiredMarkers = @(
    'BARONY_ANDROID_RUNTIME_ACTIVITY_READY',
    'BARONY_ANDROID_GAME_ENTRY',
    'BARONY_ANDROID_PATHS_READY',
    'BARONY_ANDROID_GL_ES_READY',
    'BARONY_ANDROID_GL_CAPS',
    'BARONY_ANDROID_FRAMEBUFFER_POLICY',
    'BARONY_ANDROID_FRAMEBUFFER_READY',
    'BARONY_ANDROID_GAME_INITIALIZED',
    'BARONY_ANDROID_MAIN_MENU_READY'
)
$AudioMarkers = @(
    'BARONY_ANDROID_AUDIO_READY',
    'BARONY_ANDROID_AUDIO_BUFFER_CONFIG',
    'BARONY_ANDROID_AUDIO_STREAM_OPEN',
    'BARONY_ANDROID_AUDIO_PCM_READY',
    'BARONY_ANDROID_AUDIO_SOURCE_PLAY',
    'BARONY_ANDROID_AUDIO_SFX_PLAY',
    'BARONY_ANDROID_AUDIO_STREAM_RECOVERED',
    'BARONY_ANDROID_AUDIO_CHANNELS'
)
$RendererMarkers = @(
    'BARONY_ANDROID_GL_CAPS',
    'BARONY_ANDROID_FRAMEBUFFER_POLICY',
    'BARONY_ANDROID_FRAMEBUFFER_READY',
    'BARONY_ANDROID_LIGHTMAP_FORMAT',
    'BARONY_ANDROID_HDR_MODE'
)
$InputMarkers = @(
    'BARONY_ANDROID_INPUT_DEVICE_SCAN',
    'BARONY_ANDROID_TOUCH_VISIBILITY',
    'BARONY_ANDROID_TOUCH_LAYOUT'
)
$DlcMarkers = @(
    'BARONY_ANDROID_DLC_ENTITLEMENT pack=mythsandoutcasts',
    'BARONY_ANDROID_DLC_ENTITLEMENT pack=legendsandpariahs',
    'BARONY_ANDROID_DLC_ENTITLEMENT pack=desertersanddisciples'
)

$StartupDeadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
$AppProcessId = $null
$StartupLogText = ''
$ObservedStartupMarkers = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
)
$ObservedDiagnosticMarkers = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
)
Write-Host "Waiting up to $StartupTimeoutSeconds seconds for startup, renderer, and input markers..."
do {
    $CandidateProcessId = Get-AppProcessId
    if ($CandidateProcessId) {
        $AppProcessId = $CandidateProcessId
    }
    $StartupLogText = (@(Invoke-Adb -Arguments $LogcatArguments) -join [Environment]::NewLine)
    if ($InstalledBuildIsDebuggable) {
        $StartupGameMarkers = @(Invoke-Adb -Arguments @(
            'shell', 'run-as', $PackageName,
            'grep', 'BARONY_ANDROID_', 'files/barony-output/log.txt'
        ) -AllowFailure)
        $StartupLogText += [Environment]::NewLine + (
            $StartupGameMarkers -join [Environment]::NewLine
        )
    }
    foreach ($Marker in $RequiredMarkers) {
        if ($StartupLogText -match [regex]::Escape($Marker)) {
            [void]$ObservedStartupMarkers.Add($Marker)
        }
    }
    foreach ($Marker in @(
            $RendererMarkers + $InputMarkers + $AudioMarkers + $DlcMarkers)) {
        if ($StartupLogText -match [regex]::Escape($Marker)) {
            [void]$ObservedDiagnosticMarkers.Add($Marker)
        }
    }
    $MissingAtStartup = @($RequiredMarkers | Where-Object {
        -not $ObservedStartupMarkers.Contains($_)
    })
    $MissingRendererAtStartup = @($RendererMarkers | Where-Object {
        -not $ObservedDiagnosticMarkers.Contains($_)
    })
    $MissingInputAtStartup = @($InputMarkers | Where-Object {
        -not $ObservedDiagnosticMarkers.Contains($_)
    })
    $MissingDlcAtStartup = @($DlcMarkers | Where-Object {
        -not $ObservedDiagnosticMarkers.Contains($_)
    })
    if (
        $MissingAtStartup.Count -eq 0 -and
        $MissingRendererAtStartup.Count -eq 0 -and
        $MissingInputAtStartup.Count -eq 0 -and
        $MissingDlcAtStartup.Count -eq 0
    ) {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $StartupDeadline)

if (-not $AppProcessId) {
    $AppProcessId = Get-AppProcessId
}

$AudioFlingerStart = @(Invoke-Adb -Arguments @('shell', 'dumpsys', 'media.audio_flinger') -AllowFailure)
$AudioFlingerStart | Set-Content -LiteralPath (Join-Path $OutputDirectory 'audioflinger-start.txt') -Encoding UTF8
$StartUnderruns = if ($AppProcessId) {
    Get-AudioUnderrunMaximum -AudioFlingerLines $AudioFlingerStart -AppProcessId $AppProcessId
}
else {
    $null
}

if ($DurationMinutes -gt 0) {
    $TestEnd = (Get-Date).AddMinutes($DurationMinutes)
    Write-Host "Play normally for $DurationMinutes minute(s). The script will leave the app running when it finishes."
    while ((Get-Date) -lt $TestEnd) {
        $RemainingSeconds = [Math]::Max(0, [int]($TestEnd - (Get-Date)).TotalSeconds)
        $Percent = [Math]::Min(100, [int](100 * (1 - ($RemainingSeconds / ($DurationMinutes * 60.0)))))
        Write-Progress -Activity 'Barony physical-device test' -Status "$RemainingSeconds seconds remaining" -PercentComplete $Percent
        Start-Sleep -Seconds ([Math]::Min(10, [Math]::Max(1, $RemainingSeconds)))
    }
    Write-Progress -Activity 'Barony physical-device test' -Completed
}

$LogcatLines = @(Invoke-Adb -Arguments $LogcatArguments)
$LogcatPath = Join-Path $OutputDirectory 'logcat.txt'
$LogcatLines | Set-Content -LiteralPath $LogcatPath -Encoding UTF8
$LogText = $LogcatLines -join [Environment]::NewLine
$GameLogLines = if ($InstalledBuildIsDebuggable) {
    @(Invoke-Adb -Arguments @(
        'shell', 'run-as', $PackageName, 'cat', 'files/barony-output/log.txt'
    ) -AllowFailure)
}
else {
    @('Internal game log unavailable: installed APK is correctly non-debuggable.')
}
$GameLogPath = Join-Path $OutputDirectory 'game-log.txt'
$GameLogLines | Set-Content -LiteralPath $GameLogPath -Encoding UTF8
$GameLogText = $GameLogLines -join [Environment]::NewLine
$CombinedLogText = $LogText + [Environment]::NewLine + $GameLogText

$MemoryInfoLines = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'meminfo', $PackageName
) -AllowFailure)
$MemoryInfoLines | Set-Content -LiteralPath (Join-Path $OutputDirectory 'meminfo.txt') -Encoding UTF8

$AudioFlingerEnd = @(Invoke-Adb -Arguments @('shell', 'dumpsys', 'media.audio_flinger') -AllowFailure)
$AudioFlingerEnd | Set-Content -LiteralPath (Join-Path $OutputDirectory 'audioflinger-end.txt') -Encoding UTF8
$EndUnderruns = if ($AppProcessId) {
    Get-AudioUnderrunMaximum -AudioFlingerLines $AudioFlingerEnd -AppProcessId $AppProcessId
}
else {
    $null
}

foreach ($Marker in $RequiredMarkers) {
    if ($LogText -match [regex]::Escape($Marker)) {
        [void]$ObservedStartupMarkers.Add($Marker)
    }
}
foreach ($Marker in @(
        $RendererMarkers + $InputMarkers + $AudioMarkers + $DlcMarkers)) {
    if ($CombinedLogText -match [regex]::Escape($Marker)) {
        [void]$ObservedDiagnosticMarkers.Add($Marker)
    }
}
$MissingMarkers = @($RequiredMarkers | Where-Object {
    -not $ObservedStartupMarkers.Contains($_)
})
$ObservedAudioMarkers = @($AudioMarkers | Where-Object {
    $ObservedDiagnosticMarkers.Contains($_)
})
$MissingAudioMarkers = @($AudioMarkers | Where-Object {
    -not $ObservedDiagnosticMarkers.Contains($_)
})
$ObservedRendererMarkers = @($RendererMarkers | Where-Object {
    $ObservedDiagnosticMarkers.Contains($_)
})
$MissingRendererMarkers = @($RendererMarkers | Where-Object {
    -not $ObservedDiagnosticMarkers.Contains($_)
})
$ObservedInputMarkers = @($InputMarkers | Where-Object {
    $ObservedDiagnosticMarkers.Contains($_)
})
$MissingInputMarkers = @($InputMarkers | Where-Object {
    -not $ObservedDiagnosticMarkers.Contains($_)
})
$ObservedDlcMarkers = @($DlcMarkers | Where-Object {
    $ObservedDiagnosticMarkers.Contains($_)
})
$MissingDlcMarkers = @($DlcMarkers | Where-Object {
    -not $ObservedDiagnosticMarkers.Contains($_)
})
$DlcEntitlementStates = [ordered]@{}
foreach ($Match in [regex]::Matches(
        $CombinedLogText,
        'BARONY_ANDROID_DLC_ENTITLEMENT pack=([a-z]+) enabled=([01]) source=([a-z-]+)')) {
    $DlcEntitlementStates[$Match.Groups[1].Value] =
        "enabled=$($Match.Groups[2].Value) source=$($Match.Groups[3].Value)"
}
$CrashPattern = 'FATAL EXCEPTION|Fatal signal|ANR in com\.zhdan\.baronyport|am_crash|BARONY_ANDROID_STARTUP_FAILED|BARONY_ANDROID_FRAMEBUFFER_INCOMPLETE|BARONY_ANDROID_SHADER_(?:COMPILE|LINK)_FAILED|BARONY_ANDROID_GL_OUT_OF_MEMORY|GL_INVALID_FRAMEBUFFER_OPERATION'
$CrashLines = @($LogcatLines + $GameLogLines | Where-Object { $_ -match $CrashPattern })

$ChannelSamples = [System.Collections.Generic.List[object]]::new()
foreach ($Line in $LogcatLines + $GameLogLines) {
    if ($Line -match 'BARONY_ANDROID_AUDIO_CHANNELS active=(\d+).*?ambient=(\d+)') {
        $ChannelSamples.Add([pscustomobject]@{
            Active = [int]$Matches[1]
            Ambient = [int]$Matches[2]
        })
    }
}
$MaxActiveChannels = if ($ChannelSamples.Count) {
    ($ChannelSamples | Measure-Object Active -Maximum).Maximum
}
else {
    $null
}
$MaxAmbientChannels = if ($ChannelSamples.Count) {
    ($ChannelSamples | Measure-Object Ambient -Maximum).Maximum
}
else {
    $null
}

$UnderrunDelta = if ($null -ne $StartUnderruns -and $null -ne $EndUnderruns) {
    [Math]::Max(0, [long]$EndUnderruns - [long]$StartUnderruns)
}
else {
    $null
}
$StreamRecoveries = ([regex]::Matches($CombinedLogText, 'BARONY_ANDROID_AUDIO_STREAM_RECOVERED')).Count
$AppStillRunning = $null -ne (Get-AppProcessId)
$Failed = $MissingMarkers.Count -gt 0 `
    -or $MissingRendererMarkers.Count -gt 0 `
    -or $MissingInputMarkers.Count -gt 0 `
    -or $MissingDlcMarkers.Count -gt 0 `
    -or $CrashLines.Count -gt 0
$AudioWarning = $null -ne $UnderrunDelta -and $UnderrunDelta -gt 0
$Verdict = if ($Failed) {
    'FAIL'
}
elseif ($AudioWarning) {
    'PASS WITH AUDIO UNDERRUN WARNING'
}
else {
    'PASS'
}

$Summary = [System.Collections.Generic.List[string]]::new()
$Summary.Add("verdict=$Verdict")
$Summary.Add("serial=$TargetSerial")
$Summary.Add("app_pid=$AppProcessId")
$Summary.Add("app_running_at_end=$AppStillRunning")
$Summary.Add("duration_minutes=$DurationMinutes")
$Summary.Add("required_markers_missing=$($MissingMarkers -join ',')")
$Summary.Add("renderer_diagnostics_observed=$($ObservedRendererMarkers -join ',')")
$Summary.Add("renderer_diagnostics_missing=$($MissingRendererMarkers -join ',')")
$Summary.Add("input_diagnostics_observed=$($ObservedInputMarkers -join ',')")
$Summary.Add("input_diagnostics_missing=$($MissingInputMarkers -join ',')")
$Summary.Add("dlc_diagnostics_observed=$($ObservedDlcMarkers -join ',')")
$Summary.Add("dlc_diagnostics_missing=$($MissingDlcMarkers -join ',')")
foreach ($Pack in $DlcEntitlementStates.Keys) {
    $Summary.Add("dlc_entitlement_$Pack=$($DlcEntitlementStates[$Pack])")
}
$Summary.Add("audio_diagnostics_observed=$($ObservedAudioMarkers -join ',')")
$Summary.Add("audio_diagnostics_not_observed=$($MissingAudioMarkers -join ',')")
$Summary.Add("audio_underruns_start=$StartUnderruns")
$Summary.Add("audio_underruns_end=$EndUnderruns")
$Summary.Add("audio_underrun_delta=$UnderrunDelta")
$Summary.Add("audio_stream_recoveries=$StreamRecoveries")
$Summary.Add("audio_channel_samples=$($ChannelSamples.Count)")
$Summary.Add("audio_max_active_channels=$MaxActiveChannels")
$Summary.Add("audio_max_ambient_channels=$MaxAmbientChannels")
$Summary.Add("crash_lines=$($CrashLines.Count)")
$SummaryPath = Join-Path $OutputDirectory 'summary.txt'
$Summary | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

Write-Host ''
Write-Host "Result: $Verdict"
Write-Host "Required startup markers: $($RequiredMarkers.Count - $MissingMarkers.Count)/$($RequiredMarkers.Count)"
Write-Host "Renderer diagnostics observed: $($ObservedRendererMarkers.Count)/$($RendererMarkers.Count)"
Write-Host "Input diagnostics observed: $($ObservedInputMarkers.Count)/$($InputMarkers.Count)"
Write-Host "DLC diagnostics observed: $($ObservedDlcMarkers.Count)/$($DlcMarkers.Count)"
foreach ($Pack in $DlcEntitlementStates.Keys) {
    Write-Host "DLC entitlement $Pack`: $($DlcEntitlementStates[$Pack])"
}
Write-Host "Audio diagnostics observed: $($ObservedAudioMarkers.Count)/$($AudioMarkers.Count)"
if ($null -ne $UnderrunDelta) {
    Write-Host "Maximum app-track underrun frames: $StartUnderruns -> $EndUnderruns (delta $UnderrunDelta)"
}
else {
    Write-Warning 'The app audio-track underrun count was not available from AudioFlinger.'
}
if ($ChannelSamples.Count) {
    Write-Host "OpenAL channel telemetry: max active=$MaxActiveChannels, max ambient=$MaxAmbientChannels"
}
if ($MissingMarkers.Count) {
    Write-Warning "Missing required markers: $($MissingMarkers -join ', ')"
}
if ($MissingRendererMarkers.Count) {
    Write-Warning "Missing renderer diagnostics: $($MissingRendererMarkers -join ', ')"
}
if ($MissingInputMarkers.Count) {
    Write-Warning "Missing input diagnostics: $($MissingInputMarkers -join ', ')"
}
if ($MissingDlcMarkers.Count) {
    Write-Warning "Missing DLC diagnostics: $($MissingDlcMarkers -join ', ')"
}
if ($CrashLines.Count) {
    Write-Warning "Potential crash/startup-failure lines: $($CrashLines.Count)"
}
Write-Host "Summary: $SummaryPath"
Write-Host "Logcat: $LogcatPath"
Write-Host "Game log: $GameLogPath"

if ($Failed) {
    exit 1
}
