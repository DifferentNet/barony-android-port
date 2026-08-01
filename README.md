# Barony Android Port

[![Android CI](https://github.com/DifferentNet/barony-android-port/actions/workflows/android-ci.yml/badge.svg)](https://github.com/DifferentNet/barony-android-port/actions/workflows/android-ci.yml)

This repository contains a community-maintained native Android port of Barony by Victor Jdanov. It is published with permission from Turning Wheel LLC and is based on the official Barony v5.0.2 source at commit `962a5ce36d10207beef7d8673876e0cebf8e76e4`.

The Android package contains engine code and open-source dependency notices only. It does not contain Barony maps, models, music, sounds, DLC, or other commercial game data. A purchased Barony v5.0.2 PC installation is required.

Download the APK and owned-data archive builder from the
[GitHub releases page](https://github.com/DifferentNet/barony-android-port/releases).
The current normal prerelease is
[Barony Android Port 5.0.2 Beta 7](https://github.com/DifferentNet/barony-android-port/releases/tag/5.0.2-android-beta7).
Run the builder on a Windows PC with an owned Steam or GOG Barony v5.0.2
installation, copy the generated ZIP to the Android device, then select
**Import archive** when the port starts. The ZIP remains the user's private
commercial data and must not be shared.

Beta 4 users who want to enable owned DLC must download the archive builder
from Beta 5 or newer, create a new owned-data ZIP, and import it through
**Data & Saves**. Archives created with the older builder do not contain the
DLC entitlement transfer file. Beta 5 archives remain compatible with Beta 7
and do not need to be rebuilt.

See [ANDROID.md](ANDROID.md) for checksum verification, installation
alternatives, controls, save backups, limitations, and source-build
instructions. Releases also include checksums and an ADB data installer for
advanced fallback use.

## Gameplay video

Watch [Beta 7 gameplay on real Android hardware](https://youtu.be/J8Br5tbCRcI),
including touch controls and physical-controller support.

## Current Android support

- Native `arm64-v8a` build for Android 8.0 and newer.
- OpenGL ES 3 rendering.
- Offline single-player gameplay.
- Physical gamepads and automatic on-screen touch controls.
- 720p, 1080p, and native 3D render-resolution presets with native-resolution
  menus and text.
- 60, 90, and 120 FPS limits.
- Music and sound through OpenAL Soft.
- App-specific game-data storage without broad storage permissions.
- In-app import of validated owned-data ZIP archives.
- Owned DLC entitlement transfer from Steam cached app tickets or GOG/DRM-free
  license keys.
- Portable save/settings export and import from the main menu.

Multiplayer services, achievements, workshop integration, and public-store packaging are not currently supported.

GPU compatibility testing is ongoing. Use the normal beta for general testing;
focused prereleases on the releases page are intended for the affected devices
described in their release notes.

Report Android problems with the
[structured Android bug form](https://github.com/DifferentNet/barony-android-port/issues/new?template=android-bug-report.yml).
Include the device, GPU, Android version, build, selected render/FPS preset,
and reproduction steps. Never attach owned game-data archives, DLC entitlement
files, Steam configuration, credentials, or other private commercial data.

---

## Original Barony README

![Linux-CI_fmod_steam](https://github.com/TurningWheel/Barony/workflows/Linux-CI_fmod_steam/badge.svg) ![Linux-CI_fmod_steam_eos](https://github.com/TurningWheel/Barony/workflows/Linux-CI_fmod_steam_eos/badge.svg)

# Update - 3rd October 2023

The current 'develop' branch contains in-development features for our latest update. For bugfixes + PRs, open them against 'master'.

# Compilation Instructions

The compilation instructions can be found in [INSTALL.md](INSTALL.md)

# Open-source Announcement Letter

Well here it is, as promised: the open source release of Barony. Keep in mind you still need a purchased copy of Barony to play this. I'd recommend that you thumb through all of the included text files to get a feeling of other things you'll need to build the game and check out the included licenses as well.

Many thanks go to Ciprian Elies for his original contributions to the game code, as well as for the build systems, config files, and support libraries that he developed for the project over the years. In the future, he plans to head up development on some new stuff for Barony, so keep an eye out for that.

This project was a first for both of us in many ways and it shows. Since all of the original code was written in C and hastily converted to C++ in the past few months, experienced C++ programmers may be horrified at some of the kludge we had to write to get some of the more basic systems working properly. There's not a lot of module organization either since I didn't understand how to properly write projects that scale when I started the code three years ago. Prepare to deal with lots of global variables that get used all over the project indiscriminately.

Despite the project's shortcomings, I'm reasonably proud of how the end product turned out. Writing good games is about more than just writing good code, though I guarantee we'll be taking all of the lessons learned from Barony into our next project.

I'm not sure how many people will be interested in working on this, and it may take a while for anything substantial to get going here, but I'd be pleased to see some coordinated efforts take place on this code sometime in the coming years.

Some project ideas:

 * Add an extra hard mode to the game.
 * Add a dungeon with infinite levels.
 * Create a dedicated server.
 * Multithread the packet handler.
 * Multithread the entity logic.
 * Add script support for entities and items.
 * Add persistent levels and servers.
 * Add fully 3D physics and world geometry.
 * Renovate the OpenGL code to a modern standard.

Have fun,

Sheridan
June 27th 2016
