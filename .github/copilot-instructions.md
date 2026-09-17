# LinkDrop

Flutter Android app: share-to-download manager. Receives a URL via the Android Share Sheet, resolves the downloadable resource, downloads it, and shows it in a local library.

## Stack
- Flutter (Dart), Android only.
- UI/theming: `theme` package at `/Users/ashvinijangid/Desktop/android/theme` (path dependency) — use its `ThemeX` components instead of raw Material widgets wherever one exists.
- `receive_sharing_intent` for the Share Sheet, `dio` for HTTP resolution/download, `sqflite` for the local library index, `open_filex` to open downloaded files, `permission_handler` for storage permission.

## Structure
- `lib/models` — `DownloadItem` + status enum.
- `lib/services` — `ShareIntentService` (share sheet), `LinkResolver` (probes a URL for filename/mime/size), `DownloadManager` (orchestrates + persists downloads), `DatabaseService` (sqflite).
- `lib/screens/library_screen.dart` — main/only screen: download list + share-confirm flow.
- `lib/widgets` — `DownloadTile`, `ShareConfirmSheet`.

## Conventions
- compileSdk is pinned to 37 in `android/app/build.gradle.kts` (required by `receive_sharing_intent`; keep in sync if the plugin bumps it further).
- Downloads are saved to `/storage/emulated/0/Download/LinkDrop` with a documents-dir fallback.
