# AGENTS.md — 多仪 (Duoyi)

Cross-platform productivity app: **Flutter client** (Android / Linux desktop / macOS / Web) + **single-file FastAPI backend** (`backend/main.py`, ~12k lines, SQLite). Modules: Eisenhower todos, habit heatmap, pomodoro, calendar, profile. 8 switchable themes that change colors, background images, **and UI copy** (待办 → 咒文/委托/…) — user-visible strings come from `lib/core/brand_strings.dart`, don't hardcode them. `CLAUDE.md` holds the extended version of this guidance.

## Commands

```bash
flutter pub get
flutter analyze                     # must stay clean; CI pins Flutter 3.44.1
dart format .
flutter test                        # ~240 test files under test/
flutter test test/screens/todo_screen_test.dart   # single file

# Backend (test_workspaces covers API routes; discover also includes auth/config/Web build policy)
cd backend && pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
python -m unittest discover -s . -v

# Release gate: Flutter tests + backend tests + analyze + debug APK build + device regression
scripts/alignment_regression_gate.sh
```

**Toolchains:** versions are pinned in `config/toolchain.json`. Executable locations use `FLUTTER_BIN`, `PYTHON_BIN`, Android SDK environment variables, or PATH; scripts do not assume a developer-specific installation directory.

## Hard rules (enforced by static guard tests)

~96 files named `test/**/*_static_test.dart` regex-scan `lib/` and **fail the whole suite when banned patterns appear anywhere** — e.g. locally hardcoded font weights, raw values instead of design tokens (`lib/core/design_tokens.dart`), screens not using the i18n wrapper. When one trips: read the test's `reason` message (Chinese) and fix the code — never weaken the guard. Any UI change should be checked against them.

- **Typography**: all application UI uses the bundled `NotoSansSC` variable font (Noto Sans SC, offline) through `DesignTokens.fontFamily`. Body/secondary copy, input hints, menus and snackbars use `DesignTokens.fontWeightRegular` (400); buttons, navigation labels, chips and floating labels use `DesignTokens.fontWeightMedium` (500); titles, AppBar titles and emphasis use `DesignTokens.fontWeightStrong` (600). Sizes come from the `DesignTokens.fontSize*` scale (body 16 / secondary 14 / caption 12 / page title 20); shared buttons keep `minimumSize: Size(0, DesignTokens.controlMinHeight)` with 16/10 padding so text scaling grows the control instead of clipping. Use theme text styles; do not hardcode `FontWeight` values or raw `fontFamily` strings, restore system serif/monospace families or add page-specific bottom-navigation typography. Font attribution and SIL OFL are in `assets/fonts/`; PDF export typography remains separate.
- **Web font loading**: `scripts/flutter_with_config.py build web` replaces only the generated Web FontManifest with a checked-in variable subset; the complete Noto font loads once after the first frame and idle delay. Native full-font registrations stay unchanged. Preserve this boundary; see `docs/web-font-loading.md`.
- **Subpage navigation**: use `AppPageTabs` / `AppPageSwitcher` (`lib/widgets/app_page_tabs.dart`) for content views within a screen. All themes share medium-weight labels, start alignment, horizontally scrollable labels and the short `PageTabIndicator`; avoid local pill/filled tab decorations. Date-range filters and form choices remain selection controls.

- **Version bump touches two files**: `pubspec.yaml` (`version: 1.1.41+140007`) AND `lib/core/app_version.dart` (`name`/`build`) — change together or update checks disagree.
- **Backend routes are contract-pinned**: `backend/test_workspaces.py` asserts client-facing routes do not 404. Adding/renaming a route the client calls → add/update the matching contract test; keep `API_CONTRACT_VERSION` / `API_CONTRACT_FEATURES` in `backend/main.py` current.
- **Deployment config**: public defaults live in `config/deployment.json`; inject with `python3 scripts/flutter_with_config.py ...`. Installed login supports a persisted runtime URL + access token; `DUOYI_SERVER_URL` supplies only its initial URL. Web defaults to same-origin. Use `AuthProvider.client`/`baseUrl`; credentials and local data are bound to server + account. Private backend values come from environment or ignored `backend/.env`; see `docs/configuration.md`.
- **i18n**: Chinese ARB template (`lib/l10n/app_zh.arb`, zh primary / en); use `I18n.tr()` from `lib/core/i18n.dart`.
- **Time & locale**: user-visible dates/"today"/day stats/habit periods/reminders use the *application* wall clock — `AppClock` (`lib/core/app_clock.dart`) and `LocalTimezoneResolver` (`lib/core/local_timezone_resolver.dart`), default = system zone, user-overridable IANA zone. Keep sync timestamps, `updatedAt`, IDs, elapsed timers on real instants (`DateTime.now()`/UTC) and never shift floating date-only values. Language defaults to the system locale with a persisted explicit override (`LocaleProvider`, `language_settings_tile.dart`). See `docs/configuration.md`.

## Layout

```
lib/core/        AppBrand (8 themes) / BrandStrings / design_tokens / app_config / app_version
lib/models/ lib/providers/ lib/services/ lib/screens/ lib/widgets/
backend/main.py  FastAPI monolith: /api/auth, /api/sync, /api/admin, /api/ai/chat, /ws/*
android/app/src/main/kotlin/…  Kotlin home-screen widgets (todo/habit/pomodoro), `duoyi://` deep links;
                               widget resource contracts guarded by test/services/android_widget_resources_test.dart
macos/Runner/     Flutter desktop entry + draggable native pomodoro NSPanel; see docs/macos.md.
docs/            canonical requirement/design/contract docs (requirement-v2.md, design-v2.md, cloud-sync-v2-contract.md)
```

Cloud sync (`lib/providers/cloud_sync_provider.dart` + `/api/sync/*`): timestamp-based 3-way merge, last-write-wins on `updatedAt`; contract in `docs/cloud-sync-v2-contract.md`.

## Docs & deployment hygiene

- Root-level `*_REPORT.md` / `*_SUMMARY.md` / `*_ANALYSIS.md` files are historical working-session notes — not current guidance, and don't add new ones to the root.
- Backend service/container name and runner are configured in the deployment profile. For Docker code/image or Compose env_file changes, build the image and recreate the container; restart alone preserves the old image/environment. `scripts/deploy_backend_prod.sh` restarts and verifies the configured runner; `--check-config` only inspects values. Client releases ship through the configured Fork; bump both version files before a release tag.
- Sign-off repo secrets (`DUOYI_KEYSTORE_*`) are required for release builds — no debug-signing fallback.

## Screenshots & evidence

- Store UI verification screenshots in `evidence/screenshots/`.
- Store larger screenshot batches in a named directory under `evidence/`.
- Do not leave generated agent screenshots in the repository root.
- Keep real app image assets in their existing asset directories, such as `assets/`, `android/app/src/main/res/`, `ios/Runner/Assets.xcassets/`, `linux/`, and `web/`.
