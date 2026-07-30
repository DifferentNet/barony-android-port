[CmdletBinding()]
param(
    [string]$Serial,
    [string]$ApkPath,
    [ValidateSet('Startup', 'Gameplay', 'Performance')]
    [string]$Profile = 'Gameplay',
    [ValidateRange(0, 1440)]
    [int]$DurationMinutes,
    [ValidateRange(10, 300)]
    [int]$StartupTimeoutSeconds = 90,
    [string]$OutputDirectory,
    [ValidateSet('720p', '1080p', 'native')]
    [string]$ExpectedRenderPreset,
    [ValidateSet(60, 90, 120)]
    [int]$ExpectedFrameRate,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('DurationMinutes')) {
    $DurationMinutes = switch ($Profile) {
        'Startup' { 0 }
        'Performance' { 5 }
        default { 30 }
    }
}
if ([bool]$ExpectedRenderPreset -ne $PSBoundParameters.ContainsKey('ExpectedFrameRate')) {
    throw 'ExpectedRenderPreset and ExpectedFrameRate must be supplied together.'
}

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
    $script:LastAdbExitCode = $ExitCode
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

function Get-SurfaceLayerName {
    $LayerLines = @(Invoke-Adb -Arguments @(
        'shell', 'dumpsys', 'SurfaceFlinger', '--list'
    ) -AllowFailure)
    foreach ($Line in $LayerLines) {
        if ($Line -match '^RequestedLayerState\{(.+?SurfaceView\[com\.zhdan\.baronyport/.+?\].*?\(BLAST\)#[0-9]+)\s+parentId=') {
            return $Matches[1]
        }
    }
    foreach ($Line in $LayerLines) {
        if ($Line -match 'SurfaceView\[com\.zhdan\.baronyport/' `
                -and $Line -notmatch 'Background for ' `
                -and $Line -notmatch '^RequestedLayerState\{') {
            return $Line.Trim()
        }
    }
    return $null
}

function Get-SurfaceLatencyStats {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $PresentTimes = [System.Collections.Generic.List[long]]::new()
    foreach ($Line in $Lines | Select-Object -Skip 1) {
        if ($Line -match '^\s*\d+\s+(\d+)\s+\d+\s*$') {
            $PresentTime = [long]$Matches[1]
            if ($PresentTime -gt 0 -and $PresentTime -lt [long]::MaxValue) {
                $PresentTimes.Add($PresentTime)
            }
        }
    }

    $IntervalsMs = [System.Collections.Generic.List[double]]::new()
    for ($Index = 1; $Index -lt $PresentTimes.Count; ++$Index) {
        $Delta = $PresentTimes[$Index] - $PresentTimes[$Index - 1]
        if ($Delta -gt 0) {
            $IntervalsMs.Add($Delta / 1000000.0)
        }
    }
    if ($IntervalsMs.Count -eq 0) {
        return $null
    }

    $Sorted = @($IntervalsMs | Sort-Object)
    $AverageMs = ($IntervalsMs | Measure-Object -Average).Average
    $P50Index = [Math]::Min(
        $Sorted.Count - 1,
        [Math]::Max(0, [Math]::Ceiling($Sorted.Count * 0.50) - 1)
    )
    $P95Index = [Math]::Min(
        $Sorted.Count - 1,
        [Math]::Max(0, [Math]::Ceiling($Sorted.Count * 0.95) - 1)
    )
    return [pscustomobject]@{
        Frames = $PresentTimes.Count
        AverageIntervalMs = [double]$AverageMs
        AverageFps = 1000.0 / [double]$AverageMs
        P50IntervalMs = [double]$Sorted[$P50Index]
        P95IntervalMs = [double]$Sorted[$P95Index]
    }
}

function Get-ThermalSnapshot {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $Text = $Lines -join [Environment]::NewLine
    $Status = if ($Text -match 'Thermal Status:\s*(\d+)') {
        [int]$Matches[1]
    }
    else {
        $null
    }
    $Temperatures = [ordered]@{}
    foreach ($Match in [regex]::Matches(
            $Text,
            'Temperature\{mValue=([0-9.]+), mType=\d+, mName=([A-Za-z0-9_-]+), mStatus=(\d+)\}')) {
        $Temperatures[$Match.Groups[2].Value] = [pscustomobject]@{
            Celsius = [double]$Match.Groups[1].Value
            Status = [int]$Match.Groups[3].Value
        }
    }
    return [pscustomobject]@{
        Status = $Status
        Temperatures = $Temperatures
    }
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
$DeviceLines.Add("profile=$Profile")
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
    'BARONY_ANDROID_HDR_MODE',
    'BARONY_ANDROID_RENDER_POLICY'
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

$DisplayInfoStart = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'display'
) -AllowFailure)
$DisplayInfoStart | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'display-start.txt'
) -Encoding UTF8
$ThermalInfoStart = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'thermalservice'
) -AllowFailure)
$ThermalInfoStart | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'thermal-start.txt'
) -Encoding UTF8
$BatteryInfoStart = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'battery'
) -AllowFailure)
$BatteryInfoStart | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'battery-start.txt'
) -Encoding UTF8

$SurfaceLayerName = Get-SurfaceLayerName
if ($Profile -eq 'Performance') {
    Invoke-Adb -Arguments @(
        'shell', 'dumpsys', 'gfxinfo', $PackageName, 'reset'
    ) -AllowFailure | Out-Null
    if ($SurfaceLayerName) {
        Invoke-Adb -Arguments @(
            'shell', 'dumpsys', 'SurfaceFlinger', '--latency-clear',
            "'$SurfaceLayerName'"
        ) -AllowFailure | Out-Null
    }
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

$GfxInfoLines = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'gfxinfo', $PackageName, 'framestats'
) -AllowFailure)
$GfxInfoLines | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'gfxinfo.txt'
) -Encoding UTF8

$SurfaceLatencyLines = if ($SurfaceLayerName) {
    @(Invoke-Adb -Arguments @(
        'shell', 'dumpsys', 'SurfaceFlinger', '--latency',
        "'$SurfaceLayerName'"
    ) -AllowFailure)
}
else {
    @('Barony SurfaceView layer was not found.')
}
$SurfaceLatencyLines | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'surfaceflinger-latency.txt'
) -Encoding UTF8
$SurfaceLatencyStats = Get-SurfaceLatencyStats -Lines $SurfaceLatencyLines

$DisplayInfoEnd = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'display'
) -AllowFailure)
$DisplayInfoEnd | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'display-end.txt'
) -Encoding UTF8
$ThermalInfoEnd = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'thermalservice'
) -AllowFailure)
$ThermalInfoEnd | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'thermal-end.txt'
) -Encoding UTF8
$BatteryInfoEnd = @(Invoke-Adb -Arguments @(
    'shell', 'dumpsys', 'battery'
) -AllowFailure)
$BatteryInfoEnd | Set-Content -LiteralPath (
    Join-Path $OutputDirectory 'battery-end.txt'
) -Encoding UTF8

$ScreenshotRemote = "/sdcard/barony-device-test-$AppProcessId.png"
$ScreenshotPath = Join-Path $OutputDirectory 'screenshot.png'
Invoke-Adb -Arguments @(
    'shell', 'screencap', '-p', $ScreenshotRemote
) -AllowFailure | Out-Null
Invoke-Adb -Arguments @(
    'pull', $ScreenshotRemote, $ScreenshotPath
) -AllowFailure | Out-Null
Invoke-Adb -Arguments @(
    'shell', 'rm', '-f', $ScreenshotRemote
) -AllowFailure | Out-Null
if (-not (Test-Path -LiteralPath $ScreenshotPath -PathType Leaf)) {
    Write-Warning 'Unable to capture the device screenshot.'
}

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
$CrashPattern = 'FATAL EXCEPTION|Fatal signal|ANR in com\.zhdan\.baronyport|am_crash|BARONY_ANDROID_STARTUP_FAILED|BARONY_ANDROID_FRAMEBUFFER_INCOMPLETE|BARONY_ANDROID_SHADER_(?:COMPILE|LINK)_FAILED|BARONY_ANDROID_GL_(?:ERROR|OUT_OF_MEMORY)|GL_INVALID_(?:ENUM|VALUE|OPERATION|FRAMEBUFFER_OPERATION)'
$CrashLines = @($LogcatLines + $GameLogLines | Where-Object { $_ -match $CrashPattern })

$ObservedRenderPolicies = @(
    [regex]::Matches(
        $CombinedLogText,
        'BARONY_ANDROID_RENDER_POLICY preset=(720p|1080p|native) output=\d+x\d+ world=\d+x\d+ fps=(60|90|120) ui=native'
    ) | ForEach-Object { $_.Value } | Sort-Object -Unique
)
$ExpectedRenderPolicyObserved = $true
if ($ExpectedRenderPreset) {
    $ExpectedPolicyPattern = "BARONY_ANDROID_RENDER_POLICY preset=$([regex]::Escape($ExpectedRenderPreset)) .* fps=$ExpectedFrameRate ui=native"
    $ExpectedRenderPolicyObserved = $CombinedLogText -match $ExpectedPolicyPattern
}

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
$ThermalStart = Get-ThermalSnapshot -Lines $ThermalInfoStart
$ThermalEnd = Get-ThermalSnapshot -Lines $ThermalInfoEnd
$DisplayStartText = $DisplayInfoStart -join [Environment]::NewLine
$DisplayEndText = $DisplayInfoEnd -join [Environment]::NewLine
$DisplayRefreshStart = if ($DisplayStartText -match 'mActiveRenderFrameRate=([0-9.]+)') {
    [double]$Matches[1]
}
else {
    $null
}
$DisplayRefreshEnd = if ($DisplayEndText -match 'mActiveRenderFrameRate=([0-9.]+)') {
    [double]$Matches[1]
}
else {
    $null
}
$MemoryInfoText = $MemoryInfoLines -join [Environment]::NewLine
$TotalPssKb = if ($MemoryInfoText -match 'TOTAL PSS:\s+(\d+)') {
    [long]$Matches[1]
}
else {
    $null
}
$BatteryStartText = $BatteryInfoStart -join [Environment]::NewLine
$BatteryEndText = $BatteryInfoEnd -join [Environment]::NewLine
$BatteryLevelStart = if ($BatteryStartText -match '(?m)^\s*level:\s*(\d+)') {
    [int]$Matches[1]
}
else {
    $null
}
$BatteryLevelEnd = if ($BatteryEndText -match '(?m)^\s*level:\s*(\d+)') {
    [int]$Matches[1]
}
else {
    $null
}
$BatteryTemperatureStart = if ($BatteryStartText -match '(?m)^\s*temperature:\s*(\d+)') {
    [int]$Matches[1] / 10.0
}
else {
    $null
}
$BatteryTemperatureEnd = if ($BatteryEndText -match '(?m)^\s*temperature:\s*(\d+)') {
    [int]$Matches[1] / 10.0
}
else {
    $null
}
$Failed = $MissingMarkers.Count -gt 0 `
    -or $MissingRendererMarkers.Count -gt 0 `
    -or $MissingInputMarkers.Count -gt 0 `
    -or $MissingDlcMarkers.Count -gt 0 `
    -or $CrashLines.Count -gt 0 `
    -or -not $AppStillRunning `
    -or -not $ExpectedRenderPolicyObserved
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
$Summary.Add("profile=$Profile")
$Summary.Add("duration_minutes=$DurationMinutes")
$Summary.Add("expected_render_preset=$ExpectedRenderPreset")
$Summary.Add("expected_frame_rate=$ExpectedFrameRate")
$Summary.Add("expected_render_policy_observed=$ExpectedRenderPolicyObserved")
$Summary.Add("render_policies_observed=$($ObservedRenderPolicies -join '|')")
$Summary.Add("surface_layer=$SurfaceLayerName")
if ($SurfaceLatencyStats) {
    $Summary.Add("surface_frames_sampled=$($SurfaceLatencyStats.Frames)")
    $Summary.Add("surface_average_fps=$($SurfaceLatencyStats.AverageFps.ToString('F2', [Globalization.CultureInfo]::InvariantCulture))")
    $Summary.Add("surface_average_interval_ms=$($SurfaceLatencyStats.AverageIntervalMs.ToString('F3', [Globalization.CultureInfo]::InvariantCulture))")
    $Summary.Add("surface_p50_interval_ms=$($SurfaceLatencyStats.P50IntervalMs.ToString('F3', [Globalization.CultureInfo]::InvariantCulture))")
    $Summary.Add("surface_p95_interval_ms=$($SurfaceLatencyStats.P95IntervalMs.ToString('F3', [Globalization.CultureInfo]::InvariantCulture))")
}
$Summary.Add("thermal_status_start=$($ThermalStart.Status)")
$Summary.Add("thermal_status_end=$($ThermalEnd.Status)")
$Summary.Add("display_refresh_start_hz=$DisplayRefreshStart")
$Summary.Add("display_refresh_end_hz=$DisplayRefreshEnd")
$Summary.Add("memory_total_pss_kb=$TotalPssKb")
$Summary.Add("battery_level_start=$BatteryLevelStart")
$Summary.Add("battery_level_end=$BatteryLevelEnd")
$Summary.Add("battery_temperature_start_c=$BatteryTemperatureStart")
$Summary.Add("battery_temperature_end_c=$BatteryTemperatureEnd")
foreach ($Sensor in @('AP', 'SKIN', 'BAT')) {
    if ($ThermalStart.Temperatures.Contains($Sensor)) {
        $Summary.Add("thermal_${Sensor}_start_c=$($ThermalStart.Temperatures[$Sensor].Celsius)")
    }
    if ($ThermalEnd.Temperatures.Contains($Sensor)) {
        $Summary.Add("thermal_${Sensor}_end_c=$($ThermalEnd.Temperatures[$Sensor].Celsius)")
    }
}
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
if ($SurfaceLatencyStats) {
    Write-Host (
        'Surface pacing: {0:F2} FPS average, {1:F3} ms p50, {2:F3} ms p95 ({3} frames)' -f
        $SurfaceLatencyStats.AverageFps,
        $SurfaceLatencyStats.P50IntervalMs,
        $SurfaceLatencyStats.P95IntervalMs,
        $SurfaceLatencyStats.Frames
    )
}
Write-Host "Thermal status: $($ThermalStart.Status) -> $($ThermalEnd.Status)"
if (-not $ExpectedRenderPolicyObserved) {
    Write-Warning "Expected render policy was not observed: $ExpectedRenderPreset / $ExpectedFrameRate FPS"
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
Write-Host "Screenshot: $ScreenshotPath"

if ($Failed) {
    exit 1
}
