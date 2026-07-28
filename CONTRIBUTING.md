# Contributing

Android port changes should target the public `main` branch. Keep platform
differences behind Android-specific guards, preserve upstream desktop behavior,
and never include commercial game data, generated data archives, signing
material, credentials, or device captures.

Before submitting an Android pull request:

1. Initialize and verify the pinned dependencies with
   `.\tools\verify-android-submodules.ps1`.
2. Run the narrowest relevant clean Android build.
3. Verify the resulting APK with `.\tools\verify-android-apk.ps1`.
4. Confirm the APK contains no commercial data and requests no new permission
   unless the change explicitly requires and documents it.
5. Let the `Android CI` workflow build and verify both ARM64 APK variants.

For Android setup, build commands, controls, and current limitations, see
[ANDROID.md](ANDROID.md). The desktop build instructions remain in
[INSTALL.md](INSTALL.md).

## General guidelines

- Fork the repo.
- Create a topic branch for your change or addition.
- Write good commit messages.
- Please test and self-validate your changes.
- Submit a pull request.
- Respond to any feedback and fix any issues that may arise.
- If any commits have been made upstream, please merge in the upstream changes
  and resolve any conflicts.

We want contributing to be as painless as possible while maintaining a
consistent standard of quality. Following these guidelines, the coding style
guidelines, and avoiding haphazard gameplay-balance changes will increase the
likelihood of a pull request being accepted.

For upstream Barony questions, use the
[open-source Barony channel on Discord](https://discord.gg/xPEfdWB). There is
also a channel for Barony translations.

Models can be created and edited with the open-source
[VoxelShop](https://github.com/simlu/voxelshop) and exported to VoxLap format.

## Coding style guidelines

See the upstream
[coding style guidelines](https://docs.google.com/document/d/1Wx-tkiNORweFd6htDOn88QG5i4ecyulMGVdXQhxhQnw/edit?usp=sharing)
on Google Docs.

Thank you for taking an interest in contributing to Barony.
