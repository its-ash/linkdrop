# LinkDrop

Share a link. Get the file.

**[Website](https://linkdrop.itsash.in)** · **[Download APK](https://github.com/its-ash/linkdrop/releases/latest/download/linkdrop.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Share to download**: share a URL from any app through the Android share
  sheet. LinkDrop finds the downloadable file behind it and downloads it.
- **Instagram**: share a reel or post (including `/share/` links) to save its
  video or photos in full quality, every slide of a carousel included. No login.
- **Fast downloads**: big files are fetched over up to 8 connections at once,
  and dropped connections resume where they stopped.
- **Library**: every download is kept in a local library you can browse and open.
- **No account**: everything stays on your phone.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update LinkDrop from it.
- **APK**: download the [latest APK](https://github.com/its-ash/linkdrop/releases/latest/download/linkdrop.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package.

```bash
make run      # flutter run
make build    # release APK
make deploy   # bump version, build, tag, push, GitHub release (see store.mk)
```

Check Instagram extraction from the desktop, without a phone:

```bash
dart run tool/ig_check.dart --download /tmp/ig 'https://www.instagram.com/reel/<code>/'
```

To try the share flow, share a link (a direct image, PDF or video URL) to
LinkDrop from another app, or use `adb`:

```bash
adb shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "https://example.com/file.pdf" \
  com.itsash.linkdrop/.MainActivity
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `linkdrop.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/
├── main.dart
├── models/
├── screens/      # library screen and friends
├── services/     # download manager, Instagram extractor, parallel downloader
├── utils/
└── widgets/
tool/ig_check.dart  # command-line Instagram extraction check
index.html        # landing page (GitHub Pages, linkdrop.itsash.in)
```

Stack: Flutter (Android), [`theme`](https://github.com/its-ash/theme),
`receive_sharing_intent`, `dio`, `sqflite`, `open_filex`, `permission_handler`.

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
