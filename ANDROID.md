# Barony Android Port

This is a native Android port of Barony maintained by Victor Jdanov and published with permission from Turning Wheel LLC.

The APK is code-only. It does not contain the commercial Barony game data, so every player must own a compatible Barony v5.0.2 PC installation and deploy that data locally.

## Supported configuration

- Android 8.0/API 26 or newer.
- 64-bit ARM device (`arm64-v8a`).
- OpenGL ES 3.0 or newer.
- Landscape orientation.
- Offline single-player.
- Physical gamepad, mouse and keyboard, or on-screen touch controls.

The port has been tested on a Samsung Galaxy S24 Ultra with an Adreno 750 GPU and a GameSir G8 controller.

## Install a release

You need:

- the APK and matching `.sha256` file from the GitHub release;
- a purchased Windows installation of Barony v5.0.2.

Verify the APK before installing it:

```powershell
(Get-FileHash .\Barony-Android-Port-5.0.2-android-beta1-arm64-v8a.apk -Algorithm SHA256).Hash.ToLowerInvariant()
Get-Content .\Barony-Android-Port-5.0.2-android-beta1-arm64-v8a.apk.sha256
```

The two hashes must match.

Download the APK on the Android device and open it. Android may ask you to allow
your browser or file manager to install unknown apps. This permission can be
disabled again after installation.

Launch **Barony Android Port** once. The initial data message creates the target
folder:

`Android/data/com.zhdan.baronyport/files/barony-data`

Copy the **contents** of the PC Barony installation into `barony-data`. Do not
create another `Barony` directory inside it. The resulting layout must include:

```text
barony-data/
  books/
  data/
  fonts/
  images/
  items/
  lang/
  maps/
  models/
  music/
  sound/
  gamecontrollerdb.txt
  npcnames-female.txt
  npcnames-male.txt
  playernames-female.txt
  playernames-male.txt
  scores.dat
  scores_multiplayer.dat
```

Copying the complete contents is acceptable for private use, although Windows
executables, SDKs, `_barony-source`, videos, holiday themes, and `models.cache`
are not used by the Android port and can be omitted.

Return to the game and select **Retry**. When no deployment manifest is present,
the app checks pinned hashes for the supported v5.0.2 data and creates the
manifest itself. Modified or incompatible critical files are rejected with a
clear error.

### If `Android/data` is inaccessible

Android 11 and newer restrict access to `Android/data`. Some desktop USB file
browsers and device file managers can still copy to the app-specific folder,
while others hide or reject it. The Android port deliberately does not request
broad storage permissions to bypass this protection.

The reliable fallback is the data-installer script included with the release.
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
& $adb devices
& $adb install -r .\Barony-Android-Port-5.0.2-android-beta1-arm64-v8a.apk
```

If Platform Tools is installed somewhere else, set `ANDROID_SDK_ROOT` to the directory containing `platform-tools`.

The game validates deployed data before starting and displays a detailed error
if anything is missing or incompatible.

## Updating and saves

Install updates with `adb install -r`; do not uninstall the app first. Android removes app-specific files when an app is uninstalled, including internal saves.

Barony uses one-shot checkpoints. Loading an adventure consumes its current checkpoint, and the replacement checkpoint is written at a later dungeon-level boundary. Do not test save persistence by loading a valuable adventure and immediately quitting to the main menu.

## Controls

Physical SDL-compatible gamepads are supported and preferred. Connecting a gamepad hides the touch overlay; disconnecting it restores the current touch layout.

Without a gamepad, the port selects one of three touch layouts automatically:

- **Menu:** D-pad and compact face/shoulder buttons, with direct menu tapping.
- **Gameplay:** floating movement and camera zones plus nearby action controls.
- **Inventory/UI:** centered navigation controls with direct inventory and interface tapping.

Mouse and keyboard input are also supported through Android.

## Current limitations

- Offline single-player is the tested mode.
- Steamworks, EOS, PlayFab, achievements, workshop integration, and voice chat are disabled.
- Controller glyph selection has not been verified across a broad range of controller models.
- Direct game-data copying depends on whether the phone exposes its app-specific
  `Android/data` folder. The reliable fallback requires Windows, PowerShell, and
  ADB.
- Touch layout customization, haptics, and left-handed presets are not implemented.
- In-app archive or folder import is not implemented.

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

## Signed release builds

Create a local signing identity once:

```powershell
.\tools\create-release-keystore.ps1 -GeneratePasswordFile
```

Back up the generated keystore and password securely. Losing the signing key prevents future APKs from updating an installed release.

Build and verify a signed release:

```powershell
.\tools\build-release.ps1 -Clean -VersionName 5.0.2-android-beta1 -VersionCode 5000201
```

The release script verifies:

- the APK signature, package identity, version, and SDK levels;
- a non-debuggable manifest with no requested Android permissions;
- the exact ARM64 native-library set;
- all required open-source notices;
- the absence of commercial game-data paths and unexpected APK assets.

It writes the APK, SHA-256 checksum, build metadata, and standalone data installer under ignored `android\artifacts\`.

## License and ownership

The Barony source is distributed under the BSD 2-Clause License. Preserve `LICENSE.txt` and all bundled dependency notices when redistributing source or binaries.

Barony, its name, game data, artwork, audio, and other commercial content belong to Turning Wheel LLC. None of that commercial data is included in this repository's Android APK.
