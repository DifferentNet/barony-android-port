# Playing Barony on a TV (Android TV / Google TV)

Barony Android Port runs on Android TV and Google TV devices. Use a gamepad, or
the TV remote for menus, and connect up to four gamepads for split-screen
couch co-op.

You need:

- An Android TV or Google TV device with a **64-bit** system (`arm64-v8a`),
  Android 8.0 or newer, and OpenGL ES 3.0. NVIDIA Shield TV is a well-known
  example. Many streaming sticks, including Chromecast with Google TV, run a
  32-bit system and can't install the port: the TV then reports that the app
  isn't compatible or can't be installed.
- At least 2 GB of RAM and about 1.5 GB of free storage.
- A Windows PC with **Barony 5.0.2** from **Steam** or **GOG**, on the same
  network as the TV. The app contains no game data, so you need to own the
  game.
- A Bluetooth or USB gamepad to play. The remote is enough for the menus.

## Step 1: make your game-data ZIP on the PC

Follow [Part 1 of the getting-started guide](GETTING-STARTED.md#part-1-make-your-game-data-zip-on-the-pc)
to create `Barony-Android-Data-5.0.2.zip`. You'll send it to the TV in Step 4.

## Step 2: install the app on the TV

Pick whichever way is easiest for you.

### Option A: a file-sharing app

1. On the TV, install a file-sharing app from the Play Store, such as
   *Send Files to TV*, and install the same app on your phone or PC.
2. Download the file ending in **`-arm64-v8a.apk`** from the
   [latest release](https://github.com/DifferentNet/barony-android-port/releases)
   and send it to the TV with that app.
3. Open the APK on the TV. When Android asks, allow the file-sharing app to
   install unknown apps, then choose **Install**.

### Option B: ADB from the PC

1. On the TV, turn on developer options: open **Settings** > **System** >
   **About** and press **OK** seven times on **Android TV OS build** (or
   **Build**). The exact menu names differ between TV makers.
2. In **Settings** > **System** > **Developer options**, turn on
   **USB debugging** or **Network debugging**, and note the TV's network
   address in its network settings.
3. On the PC, install
   [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools)
   and run, using your TV's address and the downloaded APK:

   ```powershell
   adb connect 192.168.1.50:5555
   adb install -r .\Barony-Android-Port-5.0.2-android-beta11-arm64-v8a.apk
   ```

   Accept the debugging prompt that appears on the TV.

## Step 3: start Barony

Open **Barony Android Port** from the TV's app list. On the first start it shows
**Barony game data required**.

## Step 4: send the game data from the PC

1. Choose **Receive from PC**. The TV shows an address such as
   `http://192.168.1.40:8765` and a 6-digit code.
2. On the PC, open that address in a web browser.
3. Enter the code from the TV, choose `Barony-Android-Data-5.0.2.zip`, and click
   **Send**.
4. Keep the TV on that screen until the transfer finishes. The TV then checks
   and installs the data. Choose **Continue** to start the game.

Safeguards: the TV only listens while the **Receive from PC** screen is open. It
stops after one file, after **Cancel**, when you leave the app, or after five
wrong codes. It accepts only devices on your local network.

If the page doesn't open, check that the PC and the TV are on the same network.
Guest networks and router "client isolation" settings block devices from
reaching each other.

## Controls

| Remote | In Barony |
| --- | --- |
| Arrows | Move through menus |
| **OK** | Select (like **A**) |
| **Back** | Go back (like **B**) |
| **Menu** | Pause menu |

Pair gamepads in the TV's **Settings** > **Remotes & Accessories**. Once a
gamepad is connected it takes over, and the remote's **Back** opens Barony's
menu instead of leaving the game.

## Couch co-op

1. Connect up to four gamepads.
2. Choose **Play Game** > **New** > **Local Adventure**.
3. Each player presses **A** on their own gamepad to join, picks a character,
   and presses **Ready**.

The screen splits so every player gets their own view: top and bottom for two
players, quarters for three or four. For a side-by-side split with two
players, turn on **Vertical Splitscreen** in Barony's settings.

If the game runs slowly with several players, open **Settings** and lower
**Render Resolution** to 720p.

## Mods and saves on a TV

**Data & Saves** > **Receive from PC (Wi-Fi)** also accepts:

- mod ZIPs made with the archive builder's `-Mods` option (see the
  [mods guide](MODS.md));
- save backups exported from Barony Android Port on a phone or tablet, to move
  a run from your phone to the TV;
- your PC saves, packed with the archive builder's `-Saves` option (Beta 12 or
  newer; see
  [Bring your PC saves](GETTING-STARTED.md#bring-your-pc-saves-optional)).

The TV recognizes what you sent and installs it. After mods or saves, choose
**Exit now** and open the game again.

## Common problems

| Problem | Fix |
| --- | --- |
| "App not installed" or "not compatible" | The TV runs a 32-bit system, which the port doesn't support. |
| The upload page doesn't load | Put the PC and the TV on the same network, without guest mode or client isolation. |
| "Wrong code" | Enter the 6 digits currently shown on the TV. After five wrong codes the TV stops listening; choose **Receive from PC** again for a new code. |
| The game is slow | Lower **Render Resolution** to 720p, especially in 3- or 4-player games. |

Still stuck? Open an issue with the
[Android bug form](https://github.com/DifferentNet/barony-android-port/issues/new?template=android-bug-report.yml)
and mention your TV model. Never attach your game-data ZIP.
