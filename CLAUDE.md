# LinkDrop

Flutter Android app: share-to-download manager. Receives a URL via the Android Share Sheet, resolves the downloadable resource, downloads it, and shows it in a local library.

## Stack
- Flutter (Dart), Android only.
- UI/theming: `theme` package at `/Users/ashvinijangid/Desktop/android/theme` (path dependency, v2) — use its `Ui*` components (`UiApp`, `UiCard`, `UiButton`, `UiSheet`, `UiDialog`, `context.showToast`, ...) instead of raw Material widgets wherever one exists. Colors from `context.colors` / `context.colors.tone(UiStatus.x)`, text styles from `context.text`. See `theme/COMPONENTS.md`.
- `receive_sharing_intent` for the Share Sheet, `dio` for HTTP resolution/download, `sqflite` for the local library index, `open_filex` to open downloaded files, `permission_handler` for storage permission.

## Structure
- `lib/models` — `DownloadItem` + status enum.
- `lib/services` — `ShareIntentService` (share sheet), `LinkResolver` (probes a URL for filename/mime/size), `DownloadManager` (orchestrates + persists downloads), `DatabaseService` (sqflite), `ParallelDownloader` (multi-connection Range download with per-chunk retry/resume; single-connection fallback), `InstagramExtractor` (pure Dart) + `instagram_webview.dart` (last-resort hidden WebView fetch).
- `lib/screens/library_screen.dart` — main/only screen: download list + share-confirm flow.
- `lib/widgets` — `DownloadTile`, `ShareConfirmSheet`.
- `tool/ig_check.dart` — desktop CLI to test Instagram extraction + download.

## Instagram
- `InstagramExtractor.resolvePost` follows share/short links (curl UA first: browser UAs get HTML instead of a redirect). `extractMedia` tries, in order: post page with a **desktop** Chrome UA (JSON at `xig_polaris_media.if_not_gated_logged_out`; a mobile UA gets no data), logged-out GraphQL by media id (`PolarisLoggedOutDesktopWWWPostRootContentQuery`) and by shortcode (`PolarisPostActionLoadPostQueryQuery`), the embed page, the post page with a curl UA, then the WebView. `mediaFromAnyJson` handles both the new (`video_versions`/`carousel_media`) and old (`video_url`/`edge_sidecar_to_children`) shapes. If Instagram changes again, update the doc_ids from yt-dlp's / cobalt's Instagram extractors.
- Debug from the Mac: `dart run tool/ig_check.dart [--download <dir>] '<url>'` prints which source worked. Instagram rate-limits GraphQL per IP (401 "Please wait") after many probes.
- Carousels become one library item per slide (`?img_index=N` link, `instagram_<code>_<N>.<ext>`). Files download to `<name>.part` and are renamed on completion.
- Tests: `flutter test` (`test/instagram_test.dart` parsers, `test/parallel_downloader_test.dart` against a local server).

## Conventions
- compileSdk is pinned to 37 in `android/app/build.gradle.kts` (required by `receive_sharing_intent`; keep in sync if the plugin bumps it further).
- Downloads are saved to `/storage/emulated/0/Download/LinkDrop` with a documents-dir fallback.

## Release (Ash Store)
- Published through the Ash Store kit: `store.json` (id `linkdrop`), `store.mk`, `index.html` + `CNAME` (`linkdrop.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version → build → commit, tag `vX.Y.Z`, push → GitHub release with `linkdrop.apk` → repo topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync` at the workspace root.
