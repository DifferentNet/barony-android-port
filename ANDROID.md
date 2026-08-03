# Barony Android Port

This is a native Android port of Barony maintained by Victor Jdanov and published with permission from Turning Wheel LLC.

The APK is code-only. It does not contain the commercial Barony game data, so every player must own a compatible Barony v5.0.2 PC installation and deploy that data locally.

## Supported configuration

- Android 8.0/API 26 or newer.
- 64-bit ARM device (`arm64-v8a`).
- OpenGL ES 3.0 or newer.
- Landscape orientation.
- Offline single-player and experimental direct LAN multiplayer.
- Physical gamepad, mouse and keyboard, or on-screen touch controls.

The port has been tested on a Samsung Galaxy S24 Ultra / Adreno 750 with a
GameSir G8 controller. Affected-device testers also confirmed the mobile
framebuffer compatibility path on a Galaxy Note 9 / Mali-G72 and a
Poco F7 / Adreno 825.

## Install a release

You need:

- the APK and matching `.sha256` file from the GitHub release;
- a purchased Windows installation of Barony v5.0.2.

Download signed builds from the
[GitHub releases page](https://github.com/DifferentNet/barony-android-port/releases).
Focused compatibility prereleases are test builds; use the normal beta unless its
release notes describe your device or problem.

Verify the APK before installing it:

```powershell
$apk = '.\Barony-Android-Port-5.0.2-android-beta8-arm64-v8a.apk'
(Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
Get-Content "$apk.sha256"
```

Replace the filename if you downloaded a newer or focused test build. The two
hashes must match.

Download the APK on the Android device and open it. Android may ask you to allow
your browser or file manager to install unknown apps. This permission can be
disabled again after installation.

### Recommended: import an owned-data archive

Download `Barony-Android-Data-Archive-Builder-5.0.2.ps1` from the same release
on a Windows PC containing an owned Barony v5.0.2 installation. Run:

```powershell
Unblock-File .\Barony-Android-Data-Archive-Builder-5.0.2.ps1
.\Barony-Android-Data-Archive-Builder-5.0.2.ps1
```

The builder detects default Steam and GOG installation locations, validates
the exact supported v5.0.2 data, excludes executables, SDKs, videos, caches, and
other unused files, and creates:

```text
Barony-Android-Data-5.0.2.zip
Barony-Android-Data-5.0.2.zip.sha256
```

Use `-SourcePath <path>` if Barony is installed somewhere else and
`-OutputPath <file.zip>` to select another destination.

Copy the ZIP to the Android device without extracting it. Start
**Barony Android Port**, select **Import archive**, and choose the ZIP with
Android's document picker. The app:

1. extracts into a separate staging directory;
2. rejects unsafe, unexpected, oversized, incomplete, or incompatible content;
3. verifies the pinned v5.0.2 critical-file hashes;
4. replaces existing game data only after validation succeeds.

Importing requires no broad storage permission and never places commercial data
inside the APK or repository.

### Owned DLC entitlements

The archive builder carries DLC access over from the selected owned PC
installation:

- GOG and other DRM-free installations may provide
  `mythsandoutcasts.key`, `legendsandpariahs.key`, and
  `desertersanddisciples.key`. The builder includes only keys that are present,
  and Barony's existing license-key validation runs on Android.
- Steam installations do not provide those key files. The builder checks the
  local Steam account configuration for cached app tickets `1010820`,
  `1010821`, and `1010822`, then writes only the corresponding pack names to
  the private owned-data archive.

No Steam account ID, password, ticket contents, `localconfig.vdf`, or other
Steam configuration is copied. If an owned Steam DLC is not detected, launch
Barony on that PC once so Steam refreshes its cached tickets, then rebuild the
archive.

The entitlement files are part of the user's private owned-data archive. They
must not be uploaded, attached to an issue, or shared with another user. DLC
remains locked when the builder finds no matching local entitlement.

After initial setup, **Data & Saves** on Barony's main menu can import a
replacement owned-data archive. Because Barony mounts data for the lifetime of
its native process, choose **Exit now** after validation and open the port again
to apply it.

### Manual folder layout

Advanced users may still copy the PC installation's required contents directly
into:

`Android/data/com.zhdan.baronyport/files/barony-data`

The maps, models, music, and other required folders must be directly inside
`barony-data`, not inside another `Barony` directory. When no deployment
manifest exists, the app checks the pinned critical hashes and creates one.

Score history is writable user state rather than required game data. Current
Barony versions store it as `savegames/scores.json` and
`savegames/scores_multiplayer.json` in the app's internal output directory.
Do not rename those JSON files or copy legacy `scores.dat` files into
`barony-data`.

### ADB data installer fallback

Android 11 and newer restrict access to `Android/data`. Some desktop USB file
browsers and device file managers can still copy to the app-specific folder,
while others hide or reject it. The Android port deliberately does not request
broad storage permissions to bypass this protection.

The legacy data-installer script included with the release remains available.
It requires Windows, Android SDK Platform Tools, and USB debugging or Wireless
debugging. With the APK already installed, run:

```powershell
Unblock-File .\Barony-Android-Data-Installer-5.0.2.ps1
.\Barony-Android-Data-Installer-5.0.2.ps1
```

The script finds the default Windows Steam installation, validates v5.0.2,
copies only the required data, and creates the same manifest. Use
`-SourcePath <path>` when Barony is installed elsewhere and
`-Serial <adb-serial>` when more than one Android target is connected.

You can also install or update the APK through ADB:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$apk = '.\Barony-Android-Port-5.0.2-android-beta8-arm64-v8a.apk'
& $adb devices
& $adb install -r $apk
```

If Platform Tools is installed somewhere else, set `ANDROID_SDK_ROOT` to the directory containing `platform-tools`.

The game validates deployed data before starting and displays a detailed error
if anything is missing or incompatible.

## Updating and saves

Install updates over the existing app; do not uninstall first. Android removes
app-specific files when an app is uninstalled, including internal saves.

When updating from Beta 4 to Beta 5, existing game data remains playable.
To enable owned DLC, download the Beta 5 archive builder, create a new
owned-data ZIP, and import it through **Data & Saves**. Archives created with
the Beta 4 builder do not contain the DLC entitlement transfer file.

Beta 8 can be installed directly over Beta 5, Beta 6, Beta 7, or the
adaptive-HDR test build. Existing owned data, DLC entitlements, saves, and
settings remain compatible, so the archive does not need to be rebuilt for
this update.

From the root Barony main menu, select **Data & Saves**:

- **Export saves and settings** creates a portable ZIP through Android's
  document picker. It contains only `savegames/` and `config/`, plus a manifest
  with a SHA-256 hash for every file.
- **Import saves and settings** validates that archive and stages it for the
  next clean process launch. Select **Exit now**, then open the port again.

Save imports reject traversal paths, unexpected files, manifest mismatches,
modified payloads, more than 512 files, and payloads larger than 64 MiB.

Barony uses one-shot checkpoints. Loading an adventure consumes its current checkpoint, and the replacement checkpoint is written at a later dungeon-level boundary. Do not test save persistence by loading a valuable adventure and immediately quitting to the main menu.

## Controls

Physical SDL-compatible gamepads are supported and preferred. Connecting a gamepad hides the touch overlay; disconnecting it restores the current touch layout.

Without a gamepad, the port selects one of three touch layouts automatically:

- **Menu:** D-pad and compact face/shoulder buttons, with direct menu tapping.
- **Gameplay:** floating movement and camera zones plus nearby action controls.
- **Inventory/UI:** centered navigation controls with direct inventory and interface tapping.

Mouse and keyboard input are also supported through Android.

## Experimental LAN multiplayer

Beta 8 enables Barony's direct LAN host and lobby-browser paths on Android.
Put the devices on the same local network, host a multiplayer game on one
device, then open the lobby browser on the other device and join the discovered
lobby. Direct IPv4 joining is also available when network discovery is blocked.

The host listens on Barony's default UDP port `57165`. Guest/client isolation,
VPNs, mobile hotspots, and router firewall rules can prevent discovery or
joining even when both devices have Internet access. LAN play does not use
Steamworks, EOS, PlayFab, or an Internet matchmaking service.

The full-game APK requests `android.permission.INTERNET`, Android's networking
permission, for this direct LAN traffic. It continues to request no storage,
account, microphone, location, or other permissions.

## Graphics and performance

The **Settings → Video** screen provides mobile performance presets:

- **Render Resolution:** 720p, 1080p, or Native. The setting scales the 3D
  world while menus, text, HUD elements, and touch coordinates remain at the
  native display resolution. Presets never upscale a display whose short edge
  is already below the selected resolution.
- **Frame Rate Limit:** 60, 90, or 120 FPS. Lower limits reduce GPU load,
  battery use, and sustained device temperature.

New installations default to the balanced 1080p render preset and a
conservative 60 FPS limit. Both settings are saved in `config/config.json` and
apply without restarting the Activity.

## Reporting Android problems

Use the
[structured Android bug form](https://github.com/DifferentNet/barony-android-port/issues/new?template=android-bug-report.yml)
and include the device model, GPU, Android version, port build, owned-data
version, selected render/FPS preset, and exact reproduction steps. Recent
`BARONY_ANDROID_*` log markers are useful when available.

Never attach owned game-data archives, DLC entitlement files, Steam
configuration, credentials, or other private commercial data to an issue.

## Current limitations

- Offline single-player remains the most broadly tested mode; direct LAN
  multiplayer is experimental.
- Internet matchmaking, Steamworks, EOS, PlayFab, achievements, workshop
  integration, and voice chat are disabled.
- Controller glyph selection has not been verified across a broad range of controller models.
- Steam DLC entitlement transfer depends on a locally cached Steam app ticket;
  launch the PC version once before rebuilding the data archive if an owned pack
  is not detected.
- HDR tone mapping uses a mobile adaptive-exposure path with GPU mip reduction
  and asynchronous 1x1 readback.
- Creating a validated owned-data archive currently requires Windows and
  PowerShell. Importing it on Android does not require ADB.
- Touch layout customization, haptics, and left-handed presets are not implemented.

## Build from source

The Android project uses:

- JDK 17;
- Android SDK/API 36;
- Android NDK `28.1.13356709`;
- CMake `3.31.4`;
- Gradle `8.11.1`;
- Android Gradle Plugin `8.9.1`.

Clone the repository with its submodules:

```powershell
git clone --recurse-submodules <repository-url>
cd <repository-directory>
```

Build the ARM64 game APK:

```powershell
.\tools\build-barony.ps1 -Clean
```

The debug APK is written under `android\artifacts\`.

Build the SDL smoke application without the game library:

```powershell
.\tools\build-smoke.ps1 -Clean
```

Build an x86-64 emulator APK explicitly:

```powershell
.\tools\build-barony.ps1 -Clean -Emulator
```

The default artifact remains ARM64-only.

Verify the pinned dependency checkout and either generated APK locally:

```powershell
.\tools\verify-android-submodules.ps1
.\tools\verify-android-apk.ps1 `
    -ApkPath .\android\artifacts\app-debug-barony-arm64-v8a.apk `
    -Variant Game `
    -Abi arm64-v8a
```

Use `-Variant Smoke` with the smoke APK immediately after a smoke build.

The `Android CI` workflow runs on pushes and pull requests targeting `main`, and
can also be started manually. It verifies all pinned Android dependency
revisions and the Gradle wrapper checksum, then builds clean smoke and full
ARM64 debug APKs. Both APKs are checked for their package/SDK metadata, exact
native-library set, strict permission boundary, allowed notice assets, and
absence of commercial game data. The smoke APK requests no permissions; the
full-game APK requests only `android.permission.INTERNET` for direct LAN play.
Successful runs retain debug-signed, non-release APKs as temporary workflow
artifacts for 14 days; these are not public releases.

Create a validated owned-data archive directly from a source checkout:

```powershell
.\tools\create-data-archive.ps1
```

Pass `-SourcePath` for a non-default Steam/GOG installation and `-OutputPath`
to choose the ZIP destination. Generated owned-data archives are private user
artifacts and must never be committed or attached to a public release.

## Physical-device regression

Run a startup-only check against the currently installed APK:

```powershell
.\tools\test-device.ps1 -SkipInstall -Profile Startup
```

Use the performance profile for a timed renderer sample:

```powershell
.\tools\test-device.ps1 `
    -SkipInstall `
    -Profile Performance `
    -DurationMinutes 5 `
    -ExpectedRenderPreset 1080p `
    -ExpectedFrameRate 60
```

The harness captures Logcat and required port markers, a screenshot, memory and
Android UI frame statistics, native SurfaceFlinger presentation timing, display
mode/refresh information, battery state, and thermal readings. It fails on
missing startup/renderer/input/DLC diagnostics, an unexpected render policy,
incomplete framebuffers, named shader or GL failures, crashes, ANRs, or native
process death. Keep the device awake and unlocked, and use `-Serial` when more
than one ADB target is connected.

## Signed release builds

Create a local signing identity once:

```powershell
.\tools\create-release-keystore.ps1 -GeneratePasswordFile
```

Back up the generated keystore and password securely. Losing the signing key prevents future APKs from updating an installed release.

Build and verify a signed release:

```powershell
.\tools\build-release.ps1 -Clean -VersionName 5.0.2-android-beta8 -VersionCode 15000222
```

Use a unique version name and a version code greater than every previously
published build when preparing a later update. Both values are mandatory.
Release builds refuse a dirty worktree by default. `-AllowDirtyWorktree` exists
only for explicitly local test artifacts; never publish an artifact made with
that override. SDK discovery honors `ANDROID_SDK_ROOT`, then `ANDROID_HOME`,
before using the default per-user Android SDK.

The release script verifies:

- the APK signature, package identity, version, and SDK levels;
- a non-debuggable manifest requesting only `android.permission.INTERNET`;
- the exact ARM64 native-library set;
- all required open-source notices;
- the absence of commercial game-data paths and unexpected APK assets.

It writes the APK, SHA-256 checksum, build metadata, standalone ADB data
installer, and owned-data archive builder under ignored `android\artifacts\`.
Build metadata records the source commit, dirty-tree state, Java/Gradle/AGP,
SDK/build-tools/NDK/CMake versions, Gradle distribution checksum, and every
pinned dependency revision.

## License and ownership

The Barony source is distributed under the BSD 2-Clause License. Preserve `LICENSE.txt` and all bundled dependency notices when redistributing source or binaries.

Barony, its name, game data, artwork, audio, and other commercial content belong to Turning Wheel LLC. None of that commercial data is included in this repository's Android APK.
