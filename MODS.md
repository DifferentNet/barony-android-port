# Mods and translations on Android

Barony Android Port plays the same mods as the PC version, through Barony's
own **Play Modded Game** menu. You install mods by importing a ZIP file. This
works for Steam Workshop mods, mods you downloaded somewhere else, and
community translations.

You need:

- Barony Android Port **Beta 10 or newer**, already set up with your game data
  (see [Getting started](GETTING-STARTED.md)).
- For Steam Workshop mods: the Windows PC with your Steam copy of Barony.

## Step 1: get a mod ZIP

### Steam Workshop mods

1. On the PC, open Steam, go to **Library** > **Barony** > **Workshop**, and
   click **Subscribe** on the mods you want. Wait until Steam finishes
   downloading them.
2. From the
   [latest release](https://github.com/DifferentNet/barony-android-port/releases),
   download **`Barony-Android-Data-Archive-Builder-5.0.2.ps1`** into your
   **Downloads** folder. Use the one from Beta 10 or newer; older builders
   can't pack mods.
3. Open **Downloads** in File Explorer, right-click an empty spot, and choose
   **Open in Terminal**. On Windows 10, hold **Shift** while right-clicking and
   choose **Open PowerShell window here**.
4. Paste this command and press **Enter**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Barony-Android-Data-Archive-Builder-5.0.2.ps1 -Mods
   ```

5. The window lists every mod it packed, and your **Downloads** folder now
   contains **`Barony-Android-Mods.zip`**.

The ZIP includes all of your Barony Workshop subscriptions, plus any mods in
the `mods` folder of your PC installation. Mods are named after their
Workshop titles, so you'll recognize them on the phone.

To pack only some mods, add `-ModName` with part of their names. `*` matches
anything, and commas separate several names:

```powershell
powershell -ExecutionPolicy Bypass -File .\Barony-Android-Data-Archive-Builder-5.0.2.ps1 -Mods -ModName "Diablo*,*Music*"
```

### A mod you downloaded as a ZIP

You can import a mod ZIP from any other source directly; skip to Step 2. The
ZIP can hold the mod's files at the top (the mod is then named after the ZIP
file) or one or more mod folders.

## Step 2: install the mods on the phone

1. Copy the ZIP to the phone, for example into its **Download** folder over a
   USB cable. **Don't unzip it.**
2. On Barony's main menu, open **Data & Saves** and choose **Import mods**.
3. Pick the ZIP. If the file picker doesn't list it, open its menu (☰) and go
   to **Downloads**.
4. When you see **Mods ready**, tap **Exit now**, then open the game again. The
   mods are installed while the game starts.

To import several ZIPs, tap **Later** after each one and **Exit now** after the
last.

## Step 3: play with mods

1. On the main menu, choose **Play Modded Game**.
2. Tap **Load Mod** next to each mod you want. **Load Order** shows the order;
   if two mods change the same thing, the one loaded last wins.
3. Tap **Start Modded Game**. Loading big mods can take a moment.

After you start a modded game, the game remembers those mods: the next time
you open **Play Modded Game**, they're already loaded. Leaving the mod menu
with **Back** unloads them.

## Translations

Community translations are mods. Subscribe to one in the Steam Workshop, pack
it with `-Mods`, import it, and load it in **Play Modded Game** like any other
mod.

## Updating or removing mods

- **Update a mod:** pack and import it again. A mod with the same name
  replaces the old copy.
- **Remove mods:** open **Data & Saves** > **Remove mods**, tick the mods,
  tap **Remove**, then **Exit now** and open the game again.

## Good to know

- Modded runs are kept separate: they use their own saves and are marked as
  modded.
- For LAN games, every player has to load the same mods.
- Browsing the Steam Workshop on the phone isn't possible. Subscribe on the PC
  instead.
- One import can be up to 2 GB, with no single file over 256 MB. Use
  `-ModName` to split very large collections.
- Mods belong to their authors. Keep your mod ZIP for your own devices.

## Common problems

| Problem | Fix |
| --- | --- |
| The builder says "No Barony mods were found" | Check that Steam finished downloading your subscriptions, and that the `-ModName` filter matches. If Barony is installed in another Steam library, add `-SourcePath` as described in [Getting started](GETTING-STARTED.md). |
| "Could not look up Steam Workshop titles" | The PC is offline or Steam's website is unreachable. The ZIP still works, but the mods are named by their Workshop numbers. |
| "No Barony mod found" on the phone | The ZIP doesn't contain Barony mod files such as `data`, `maps`, `models`, `images`, `lang`, `music`, or `preview.png`. |
| A mod isn't listed in **Play Modded Game** | Tap **Exit now** after importing and open the game again. |
| A mod doesn't work as expected | Some mods were made for other Barony versions. Try it on its own, and report problems with the [Android bug form](https://github.com/DifferentNet/barony-android-port/issues/new?template=android-bug-report.yml). Don't attach the mod ZIP. |

For technical details, see [ANDROID.md](ANDROID.md#mods-and-translations).
