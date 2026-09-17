# LinkDrop

A share-to-download manager for Android. Share a URL from any app, LinkDrop receives it through the Android Share Sheet, resolves an accessible downloadable resource, downloads it, and lists it in a local library.

## Stack

- Flutter (Android)
- [`theme`](https://github.com/its-ash/theme) — shared `ThemeX` component library
- `receive_sharing_intent`, `dio`, `sqflite`, `open_filex`, `permission_handler`

## Run

```bash
flutter pub get
flutter run
```

To try the share flow, share a link (e.g. a direct image/PDF/video URL) to LinkDrop from another app, or use `adb`:

```bash
adb shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "https://example.com/file.pdf" \
  com.itsash.linkdrop/.MainActivity
```

## Makefile

```bash
make run      # flutter run
make build    # flutter build apk --release
make deploy   # build, push to main, tag, and publish a GitHub release with the APK
```

## Product page

`index.html` at the repo root is a standalone landing page for the app (no build step — open it directly or serve the repo root).

Built by [itsash.in](https://itsash.in).
