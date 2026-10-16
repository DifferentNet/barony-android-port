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

Beta 8 and earlier were tested on a Samsung Galaxy S24 Ultra / Adreno 750
with a GameSir G8 controller. Affected-device testers also confirmed the
mobile framebuffer compatibility path on a Galaxy Note 9 / Mali-G72 and a
Poco F7 / Adreno 825. Beta 9 and Beta 10 were verified on an Android 15
emulator, including the ARM64 build under ARM translation, so reports from
physical devices are especially welcome.

## Install a release

For a short, beginner-friendly walkthrough, see
[GETTING-STARTED.md](GETTING-STARTED.md). This section covers the same steps
in more detail.

You need:

- the APK and matching `.sha256` file from the GitHub release;
- a purchased Windows installation of Barony v5.0.2.

Download signed builds from the
[GitHub releases page](https://github.com/DifferentNet/barony-android-port/releases).
Focused compatibility prereleases are test builds; use the normal beta unless its
release notes describe your device or problem.

Verify the APK before installing it:

```powershell
$apk = '.\Barony-Android-Port-5.0.2-android-beta11-arm64-v8a.apk'
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

Barony's seasonal themes (Halloween from October 1 to November 1, and the
winter holidays from December 1 to January 1) are optional. Without them, the
game starts with its normal look during those dates. To keep the seasonal
textures, music, and lighting, add `-IncludeHolidayThemes`; this adds about
170 MB to the archive. Barony's **Festive Content** setting can still turn the
theme off on the device.

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
`-SourcePath <path>` when Barony is installed elsewhere,
`-Serial <adb-serial>` when more than one Android target is connected, and
`-IncludeHolidayThemes` to also copy the optional seasonal themes.

You can also install or update the APK through ADB:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$apk = '.\Barony-Android-Port-5.0.2-android-beta11-arm64-v8a.apk'
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

Beta 11 can be installed directly over Beta 5 through Beta 10, or the
adaptive-HDR test build. Existing owned data, DLC entitlements, saves, and
settings remain compatible, so the archive does not need to be rebuilt for
this update. Rebuild it with `-IncludeHolidayThemes` only if you want the
optional seasonal themes.

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
- **Inventory/UI:** centered navigation controls with direct inventory and
  interface tapping. **LT** opens the spell list and **RT** opens the skill
  sheet.

Mouse and keyboard input are also supported through Android. Connecting both an
external keyboard and an external mouse (for example over Bluetooth) hides the
touch overlay, just like a gamepad; disconnecting either one restores it. Mouse
clicks always go to the game, never to on-screen buttons.

Local split-screen co-op works with up to four gamepads: choose
**Local Adventure** and have each player press **A** to join.

## Android TV and Google TV

For a beginner-friendly walkthrough, see [TV.md](TV.md). TV devices need a
64-bit (`arm64-v8a`) system; many streaming sticks, including Chromecast with
Google TV, run a 32-bit system and can't install the port.

The app appears in the TV's app list with a banner. On a TV, the touch overlay
is hidden and the remote drives Barony's menus: the arrows move, **OK**
selects, **Back** cancels, and **Menu** opens the pause menu. With a gamepad
connected, the gamepad takes over and the remote's **Back** acts as Escape.

TVs have no document picker, so data is installed with **Receive from PC**.

## Receive from PC

**Receive from PC (Wi-Fi)** in **Data & Saves**, and on the first-run data
screen on a TV, receives one ZIP from a web browser on another device on the
same local network. It accepts owned-data archives, mod archives, and save
backups, recognizes which kind was sent, and hands it to the same validation
and import path as the document picker.

The device shows an `http://<address>:8765` URL and a 6-digit code. Safeguards:

- It listens only while the receive screen is shown, and stops after one
  successful transfer, **Cancel**, leaving the app, or five wrong codes.
- Every upload must carry the code shown on the screen.
- It accepts connections only from private, link-local, and loopback
  addresses.
- It accepts only `.zip` files that start with a ZIP signature, up to 2 GB.
- Interrupted or rejected uploads are deleted.
- It uses the existing networking permission from LAN multiplayer and requests
  no new permission.

Router client isolation or guest networks can block the connection, as for
LAN play.

## Mods and translations

Barony's own mod menu works on Android: choose **Play Modded Game**, select
**Load Mod** for each mod you want, then **Start Modded Game**. Community
translations are ordinary mods and work the same way. For a beginner-friendly
walkthrough, see [MODS.md](MODS.md).

Mods live in the app's private storage, so they are installed from a ZIP:

1. Get a mod ZIP:
   - **Steam Workshop or local PC mods:** subscribe to mods in Barony's Steam
     Workshop (or put them in `Barony\mods` on the PC), then run the archive
     builder with `-Mods`:

     ```powershell
     powershell -ExecutionPolicy Bypass -File .\Barony-Android-Data-Archive-Builder-5.0.2.ps1 -Mods
     ```

     It creates `Barony-Android-Mods.zip` with every subscribed and local mod.
     Workshop mods are named after their Workshop titles, which the builder
     looks up through Steam's public web API (only the item IDs are sent).
     Add `-NoWorkshopTitles` to skip the lookup, or `-ModName "Title*"` to
     include only matching mods (separate several names with commas).
   - **A mod downloaded as a ZIP:** use it directly. The ZIP may contain the
     mod's files at its root (the mod is named after the ZIP file) or one or
     more mod folders.
2. Copy the ZIP to the device. On Barony's main menu, open **Data & Saves**,
   choose **Import mods**, and pick the ZIP.
3. Choose **Exit now**, then open the port again. The mods are installed before
   Barony starts.

To uninstall mods, use **Data & Saves** > **Remove mods**, then exit and reopen
the port.

Notes:

- One import may contain up to 2 GB of mods, with no single file larger than
  256 MB.
- Barony keeps modded runs separate: they use their own save files and mark
  the run as modded.
- For LAN games, every player must load the same mods by hand.
- Browsing and subscribing to the Steam Workshop isn't available on the device.
- Mods belong to their authors. Keep the generated ZIP for your own devices.

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

Never attach owned game-data archives, mod archives, DLC entitlement files,
Steam configuration, credentials, or other private commercial data to an
issue.

## Current limitations

- Offline single-player remains the most broadly tested mode; direct LAN
  multiplayer is experimental.
- Internet matchmaking, Steamworks, EOS, PlayFab, achievements, in-app Steam
  Workshop browsing, and voice chat are disabled. Mods are installed from ZIP
  archives instead (see [Mods and translations](#mods-and-translations)).
- Controller glyph selection has not been verified across a broad range of controller models.
- Steam DLC entitlement transfer depends on a locally cached Steam app ticket;
  launch the PC version once before rebuilding the data archive if an owned pack
  is not detected.
- HDR tone mapping uses a mobile adaptive-exposure path with GPU mip reduction
  and asynchronous 1x1 readback.
- Creating a validated owned-data archive currently requires Windows and
  PowerShell. Importing it on Android does not require ADB.
- Touch layout customization, haptics, and left-handed presets are not implemented.
- Barony reads some mod data files into fixed-size buffers, so a mod with an
  unusually large data file may load only partly. Barony logs a JSON error
  and skips that file, as on desktop.

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
to choose the ZIP destination. Add `-IncludeHolidayThemes` to include the
optional seasonal themes. `-Mods` builds a mod archive instead (see
[Mods and translations](#mods-and-translations)). Generated owned-data and mod
archives are private user artifacts and must never be committed or attached
to a public release.

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

For a long Galaxy A36 memory regression, keep the device at 720p / 60 FPS and
sample the process once per minute across dungeon transitions:

```powershell
.\tools\test-device.ps1 `
    -SkipInstall `
    -Profile Gameplay `
    -DurationMinutes 45 `
    -MemorySampleIntervalSeconds 60 `
    -ExpectedRenderPreset 720p `
    -ExpectedFrameRate 60
```

The harness captures Logcat and required port markers, a screenshot, memory and
Android UI frame statistics, native SurfaceFlinger presentation timing, display
mode/refresh information, battery state, and thermal readings. It fails on
missing startup/renderer/input/DLC diagnostics, an unexpected render policy,
incomplete framebuffers, named shader or GL failures, crashes, ANRs, or native
process death. Timed Gameplay and Performance runs also write raw
`meminfo-series.txt` snapshots and parsed `memory-series.csv` trends. A positive
memory trend is diagnostic and does not fail the run by itself. If the monitored
process exits or changes PID, the harness stops the timed phase and immediately
writes `crash-logcat.txt` before completing the remaining safe captures.

Keep the device awake and unlocked, and use `-Serial` when more than one ADB
target is connected. For a public OOM report, attach only
`meminfo-series.txt` and `crash-logcat.txt` when present. Never attach owned game
data, save archives, DLC entitlement files, Steam configuration, or credentials.

## Signed release builds

Create a local signing identity once:

```powershell
.\tools\create-release-keystore.ps1 -GeneratePasswordFile
```

Back up the generated keystore and password securely. Losing the signing key prevents future APKs from updating an installed release.

Build and verify a signed release:

```powershell
.\tools\build-release.ps1 -Clean -VersionName 5.0.2-android-beta11 -VersionCode 15000225
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
