# Getting started: play Barony on Android

This guide takes you from nothing to playing in about 15 minutes. You need:

- An Android phone or tablet with Android 8.0 or newer and a 64-bit ARM
  processor (almost every phone from the last few years).
- A Windows PC with **Barony 5.0.2** installed from **Steam** or **GOG**.
  The Android app contains no game data, so you need to own the game.
- About 1.5 GB of free space on the phone.

The installation has two parts. First you copy your own game data from the PC
into a ZIP file. Then you install the app on the phone and import that ZIP.

## Part 1: make your game-data ZIP on the PC

1. If you play on Steam and own DLC, start Barony on the PC once and quit.
   This lets the builder detect your DLC.
2. Open the
   [latest release](https://github.com/DifferentNet/barony-android-port/releases)
   and download **`Barony-Android-Data-Archive-Builder-5.0.2.ps1`** from the
   **Assets** list. Leave it in your **Downloads** folder.
3. Open your **Downloads** folder in File Explorer, right-click an empty spot,
   and choose **Open in Terminal**. On Windows 10, hold **Shift** while
   right-clicking and choose **Open PowerShell window here**.
4. Copy this command, paste it into the window, and press **Enter**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Barony-Android-Data-Archive-Builder-5.0.2.ps1
   ```

   This runs the downloaded script once without changing any Windows
   settings.
5. Wait until it finishes, usually in under a minute. Your **Downloads** folder
   now contains **`Barony-Android-Data-5.0.2.zip`** (about 450 MB). The window
   also lists which DLC packs were detected.

Keep this ZIP private. It contains the game files you bought, so don't upload
or share it.

If the builder says it can't find Barony, your game is installed somewhere
else. In Steam, right-click **Barony** > **Manage** > **Browse local files** to
see the folder, then add it to the command:

```powershell
powershell -ExecutionPolicy Bypass -File .\Barony-Android-Data-Archive-Builder-5.0.2.ps1 -SourcePath "D:\SteamLibrary\steamapps\common\Barony"
```

Optional: add `-IncludeHolidayThemes` to the command to keep Barony's
Halloween and Christmas looks. This makes the ZIP about 170 MB bigger.

## Part 2: install the app and import the ZIP

1. Copy **`Barony-Android-Data-5.0.2.zip`** to your phone, for example into its
   **Download** folder over a USB cable. **Don't unzip it.**
2. On the phone, open the
   [latest release](https://github.com/DifferentNet/barony-android-port/releases)
   and download the file ending in **`-arm64-v8a.apk`**.
3. Open the downloaded APK. If Android asks, allow your browser or file
   manager to install apps, then tap **Install**.
4. Start **Barony Android Port**. It shows **Barony game data required**.
5. Tap **Import archive** and choose **`Barony-Android-Data-5.0.2.zip`**. If
   the file picker doesn't list it, open its menu (☰) and go to **Downloads**.
6. Wait while the app checks and installs the data. When you see
   **Game data imported**, tap **Continue**.

The game starts. You can delete the ZIP from the phone afterwards if you want
the space back.

**No USB cable?** Any way of getting the ZIP onto the phone works. The file
picker in step 5 can also open it from Google Drive or another cloud storage
app. Later, **Data & Saves** > **Receive from PC (Wi-Fi)** can receive mods and
save backups straight from a PC browser.

## Playing on a TV

Barony also runs on 64-bit Android TV and Google TV devices, such as NVIDIA
Shield TV. Follow the step-by-step [TV guide](TV.md): it covers installing the
app on the TV, sending the game data from the PC over Wi-Fi, and the remote's
controls.

## Couch co-op

Connect up to four gamepads, choose **Play Game** > **New** >
**Local Adventure**, and have each player press **A** on their own gamepad to
join. The screen splits so every player gets their own view. This works on
phones, tablets, and TVs.

## Controls

- **Touch:** on-screen controls appear automatically and change between menus,
  gameplay, and the inventory.
- **Gamepad:** connect a Bluetooth or USB controller and the touch controls
  disappear.
- **Keyboard and mouse:** connect both and the touch controls disappear.

If the game runs slowly, open **Settings** and lower **Render Resolution** to
720p.

## Mods and translations (optional)

Steam Workshop mods, downloaded mods, and community translations all work.
In short: run the builder with `-Mods` on the PC, import the ZIP from
**Data & Saves** > **Import mods**, then load the mods in **Play Modded Game**.
Follow the step-by-step [mods guide](MODS.md).

## Updating to a new version

Download the new APK and install it over the old one. **Don't uninstall the
old app first**: uninstalling deletes your saves. Your game data stays
installed, so you don't need to import the ZIP again unless the release notes
say so.

To back up your saves, use **Data & Saves** > **Export saves and settings** on
the main menu.

## Common problems

| Problem | Fix |
| --- | --- |
| "running scripts is disabled on this system" | Use the full `powershell -ExecutionPolicy Bypass -File ...` command from Part 1, step 4. |
| The builder can't find Barony | Add `-SourcePath` with your game folder, as shown in Part 1. |
| "Unsupported or modified Barony data file" | The PC copy isn't the original Barony 5.0.2. In Steam, use **Properties** > **Installed Files** > **Verify integrity of game files**, then run the builder again. |
| DLC classes are locked | Start Barony on the PC once, build a new ZIP, and import it from **Data & Saves** > **Import owned game data**. |
| "Barony has encountered a critical error" in October or December | Update to Beta 9 or newer. |

Still stuck? Open an issue with the
[Android bug form](https://github.com/DifferentNet/barony-android-port/issues/new?template=android-bug-report.yml).
Mention your phone model and Android version, but never attach your game-data
ZIP.

For checksum verification, the ADB installer, and building from source, see
[ANDROID.md](ANDROID.md).
