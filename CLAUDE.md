# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

多仪 (Duoyi) is a cross-platform productivity app built with Flutter + FastAPI backend. It integrates todo management (Eisenhower matrix), habit tracking (GitHub-style heatmap), Pomodoro focus sessions, calendar, and personal profile into a single app. Supports 8 theme variations with custom backgrounds, AI assistant integration, cloud sync, and Android home screen widgets.

- **Frontend**: Flutter (Dart SDK ^3.11.5). CI pins Flutter **3.44.1**; the local install may be older (currently 3.41.9) — analyzer behavior differs between versions, and code must stay clean on the CI version.
- **Backend**: Python FastAPI single-file monolith with SQLite
- **State Management**: Provider pattern
- **Platforms**: Android, Linux desktop, macOS, Web (iOS scaffolding exists but is not a CI target); macOS runner and draggable pomodoro panel are documented in `docs/macos.md`.

Toolchain versions live in `config/toolchain.json`. Use `FLUTTER_BIN`, `PYTHON_BIN`, `ANDROID_SDK_ROOT` / `ANDROID_HOME`, or PATH for local executable locations; scripts must not assume an author's machine paths.

## Development Commands

### Flutter Client

```bash
flutter pub get
flutter run -d linux              # Linux desktop
flutter analyze
dart format .

# Run all tests
flutter test

# Run a single test file
flutter test test/screens/countdown_screen_test.dart

# Build an APK with an initial server URL (editable on the installed login page)
flutter build apk --release --dart-define=DUOYI_SERVER_URL=https://your-server.com
```

### Backend

```bash
cd backend
pip install -r requirements.txt

# Start development server (creates duoyi.db on first run)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Run all backend tests (unittest-style; pytest also works)
python -m unittest discover -s . -v

# Run a single backend test
python -m unittest test_workspaces.WorkspaceApiTest.test_admin_current_management_routes_do_not_404
```

`backend/test_workspaces.py` covers route contracts, auth, admin, sync, feedback and coins. Run unittest discovery to also include the separate access-token, configuration and Web-font-build policy tests.

**Backend configuration**: process environment > ignored `backend/.env` (`DUOYI_ENV_FILE`) > public `config/deployment.json` (`DUOYI_CONFIG_FILE`) > schema defaults. Only a genuinely fresh database receives the bootstrap admin (default `admin`); an empty/unset `ADMIN_BOOTSTRAP_PASSWORD` generates a random password once and saves local credentials to `<DUOYI_DB_PATH>.bootstrap-admin.json` with mode `0600` (default `backend/duoyi.db.bootstrap-admin.json`). Explicit bootstrap passwords remain supported. Existing installations never gain/reset/promote bootstrap accounts; restarts preserve password hashes, data and PASSWORD_HASH_SALT. Database runtime settings only receive missing initial values. See `docs/configuration.md` and `backend/.env.example`.

### Full Regression Gate

```bash
scripts/alignment_regression_gate.sh
```

The release gate. Runs 8 groups: batched Flutter tests (static guards, screens, notifications, widget contracts), backend route-contract tests via unittest, `flutter analyze`, a debug APK build, and a device/emulator regression (`scripts/device_regression_check.sh` — needs Android SDK + KVM). Report written to `build/alignment-regression/latest/`.

## Critical Conventions

### Static guard tests enforce project rules

About 100 of roughly 380 Flutter test files match `*_static_test.dart`. These regex-scan `lib/` source and **fail when banned patterns appear anywhere in the codebase**. Typography guards require the shared `DesignTokens.fontFamily` family and the three shared weight tokens (`fontWeightRegular` 400 / `fontWeightMedium` 500 / `fontWeightStrong` 600); local `FontWeight` literals and raw `fontFamily` strings are forbidden. When your change trips a guard, read the test's `reason` message and fix the code to comply — do not weaken the guard. Expect any UI change to be checked against them.

All brands, app controls, input text and secondary pages share `NotoSansSC` (bundled Noto Sans SC variable font, offline) through `DesignTokens.fontFamily`. Body copy, secondary copy, input hints, menus and snackbars are Regular (`DesignTokens.fontWeightRegular`, 400); buttons, navigation labels, chips and floating labels are Medium (`DesignTokens.fontWeightMedium`, 500); titles, AppBar titles and emphasis are Semibold (`DesignTokens.fontWeightStrong`, 600). Shared typography tokens remain body 14 / secondary 12 / caption 11 / page title 18. Native Android uses `DesignTokens.androidFontSizeBody = 12` through the root `AppTypography` scaler (12/14), so standard 100% renders body at 12 before system scaling and all other text roles scale proportionally. Native Android offers 55/70/85/100/115/130/145%, with default 100% in the fourth, center position and three steps on each side. Web (including Android browsers), iOS and desktop keep the shared baseline and original eight ratios 85–190%. Apply this platform base separately from user ratios and preserve nonlinear system scaling; previews must retain the base and replace only the saved application ratio. Valid saved ratios remain; an out-of-range legacy ratio normalizes to the closest available current-platform option. Ordinary loading does not rewrite the stored ratio or run a forced default migration. Keep existing account-owner and save/cancel semantics. Shared buttons use `minimumSize: Size(0, DesignTokens.controlMinHeight)` with 16/10 padding so text scaling grows the control instead of clipping. Keep the existing color/spacing hierarchy and one shared navigation style across primary pages. The font is bundled for consistent offline display; its source, checksum and SIL Open Font License live in `assets/fonts/`. PDF/report font handling is independent.

Web startup is the exception to complete offline font loading: the configured build wrapper registers one checked-in variable-font subset, then the app loads the complete Noto font after the first frame and idle delay. Native full-font registrations remain intact; rare Web glyphs may need the engine's on-demand fallback before the complete font is ready. See `docs/web-font-loading.md`.

### User configuration survives normal updates

User preferences belong in platform user storage, outside APK/`.app` bundles and Web static releases. Android, iOS, macOS, Linux and Web share the Flutter persistence/cleanup rules; their actual preference files are platform-specific. Normal in-place updates must retain saved settings and must not clear storage just because the version changed. Keep application IDs/Bundle IDs, signing identity, macOS sandbox/data-directory conventions, Linux application id/binary name and Web origin stable.

Device date/navigation/timezone/reminder settings and the selected theme survive ordinary account cleanup. Account business caches, sync baselines, notification registries and private integration credentials still follow server/account isolation. The explicit device-key list documents ownership and is checked by tests; runtime cleanup uses the account deletion lists, so do not introduce a broad `pref_*` deletion. New defaults fill missing values; any explicit migration needs documented conditions and tests preserving existing choices.

Uninstalling, clearing app/browser data, switching application identity or deliberately restoring a backup is different from an application update. Newer cloud preferences may also update local values under the sync contract. Backend deployment does not update already installed native clients. See `docs/configuration-persistence.md` for platform storage, upgrade conditions and verification limits.

### Approved cross-platform application logo

The user-approved logo is the red rounded square (`#C85656`) with three white geometric blocks shown in `docs/branding.md`. It is fixed across all platforms and themes. Use `assets/logo/duoyi_app_logo.svg` as the editable master and `assets/logo/duoyi_app_logo_1024.png` as the packaged source. Preserve `assets/logo/duoyi_logo_reference.png` as the original approval reference; do not substitute the old calendar `duoyi_logo_redesign_1024.png`, hourglass assets or a template icon.

Regenerate all platform icon resources together and verify them from the project root:

```bash
python3 scripts/sync_app_icons.py
python3 scripts/sync_app_icons.py --check
flutter test --no-pub test/services/platform_logo_assets_test.dart --reporter expanded
```

The Android adaptive foreground uses the matching transparent derivative and red background. Authentication headers use the fixed logo image instead of theme-colored icon-font recreation. Keep platform-required scaling/masking, application identity, text/layout and user data intact. Resource generation alone does not establish actual installed-app, Dock/launcher or browser-cache behavior; record those checks separately.

Browser tabs use the generated transparent `web/favicon.svg` first and a transparent 32px PNG compatibility fallback. Derive both from the master without its opaque canvas, preserve the red/white mark, and verify light/dark backgrounds. SVG does not imply transparency: do not reintroduce a fixed page-colored background rectangle or use native icon bitmaps as favicons. The browser owns tab-strip colors; `theme-color` and PWA launch backgrounds are separate concerns.

### Version bump touches two files

The app version lives in **both** `pubspec.yaml` (`version: <name>+<build>`) and `lib/core/app_version.dart` (`name` / `build`). Read the current values from those files and bump them together; historical version examples are not a release baseline.

### Backend routes are contract-pinned

`test_workspaces.py` pins every client-facing route against 404s (many tests are named `..._do_not_404`). When adding or renaming a backend route the client calls, add/update the matching contract test. `API_CONTRACT_VERSION` and `API_CONTRACT_FEATURES` in `backend/main.py` track client compatibility.

### Screenshots and evidence (from AGENTS.md)

- Store UI verification screenshots in `evidence/screenshots/`; larger batches in a named directory under `evidence/`.
- Never leave generated screenshots in the repository root.
- Real app image assets belong in their existing asset directories (`assets/`, `android/app/src/main/res/`, `ios/Runner/Assets.xcassets/`, `macos/Runner/Assets.xcassets/`, `linux/`, `web/`).

### Documentation layout

Canonical requirement/design/task docs live in `docs/`; start at `docs/README.md` and follow it to `requirement-v2.md`, `design-v2.md`, `cloud-sync-v2-contract.md`, `branding.md`, `configuration-persistence.md`, etc. The project root keeps only `README.md`, `DEPLOY.md`, `AGENTS.md`, `CLAUDE.md`, `LICENSE` and project/config entry files. One-off analysis and session handoff notes go to the session scratch directory, never the repository. Verifiable evidence lives under `evidence/`; its historical hash manifests are history records — keep them and never rewrite them to hide removed legacy file names. Build and last-run output is not committed (see `.gitignore`). Old root documents stay reachable through git history instead of an `archive/` copy.

## Architecture

### Frontend Structure

```
lib/
├── core/              # Theme system, design tokens, business logic (no Flutter UI deps for most)
│   ├── app_brand.dart         # 8 theme definitions (defaultBrand, re0, genshin, starRail, wuthering, zzz, yanyun, botw)
│   ├── brand_strings.dart     # Theme-specific UI text (e.g., "待办" → "咒文" in RE0 theme)
│   ├── app_config.dart        # Validated, immutable public build configuration; values injected from config/deployment.json
│   ├── app_version.dart       # App version constants (keep in sync with pubspec.yaml)
│   ├── design_tokens.dart     # Spacing/typography tokens (enforced by static guard tests)
│   └── ...                    # achievements, report_engine, recurrence, insights, validation, etc.
├── models/            # Data models (Todo, Habit, Pomodoro, CalendarEvent, UserProfile, Goal, etc.)
├── providers/         # Provider state management (TodoProvider, HabitProvider, CloudSyncProvider, etc.)
├── services/          # API clients, platform integrations (ApiClient, AiService, SystemTray, DeepLinkService)
├── screens/           # UI screens (admin_screen, calendar_screen, habit_detail_screen, etc.)
└── widgets/           # Reusable widgets (eisenhower matrix, heatmap, brand_background, etc.)
```

### Backend Structure

**Single-file monolith**: `backend/main.py` (~12,400 lines)

- FastAPI app with SQLite at `backend/duoyi.db` (auto-created; a legacy `fingertip_time.db` is auto-detected and preferred only if it holds more data; override path via `DUOYI_DB_PATH`)
- Routes: `/api/auth/*`, `/api/sync/*`, `/api/admin/*`, `/api/ai/chat`, `/api/focus-rooms/*`, `/api/theme-shop/*`, `/ws/*`
- Admin panel settings stored in database, read via API (AI config, cloud backup settings, announcements, user management)

### Theme System

The app uses a **brand/theme system** that switches not just colors but also:
- Background images (7 themed backgrounds in `assets/backgrounds/`)
- UI terminology (e.g., "待办" becomes "咒文" in RE0 theme, "委托" in Genshin theme)
- Greeting messages and notification text

Theme switching is managed by `AppBrand` (`lib/core/app_brand.dart`) and `BrandStrings` (`lib/core/brand_strings.dart`).

### Cloud Sync

- **Client**: `lib/providers/cloud_sync_provider.dart` implements timestamp-based 3-way merge
- **Server**: `/api/sync/push` and `/api/sync/pull` endpoints in `backend/main.py`
- Sync payloads: todos, habits, calendar events, pomodoro sessions, notes, diaries, goals, courses, etc.
- Conflict resolution: last-write-wins based on `updatedAt` timestamps
- Configurable via admin panel: max payload size, minimum sync interval, retention days
- Contract doc: `docs/cloud-sync-v2-contract.md`

### Android Widgets

- **Location**: `android/app/src/main/kotlin/com/.../`
- **Type**: MIUI/generic home screen widgets with 3 columns (todo, habit, pomodoro)
- **Deep links**: `duoyi://` scheme for widget tap actions
- Widget resource contracts are guarded by `test/services/android_widget_resources_test.dart` (and an iOS counterpart)

## Build & Release

### CI/CD (GitHub Actions)

Workflow `.github/workflows/build-apk.yml` validates a shared profile first and reads toolchain versions from `config/toolchain.json`.

| Trigger | Job | Output |
|---------|-----|--------|
| Push to `main` / `self-hosted-skydrow` / `build/macos-dmg` / `fix/android-input-settings-device-test`, push a `v*` tag, or PR targeting `main` / `self-hosted-skydrow` | `configuration` → `analyze` | Shared profile validation, `flutter analyze`, complete Flutter tests and backend tests |
| Same triggers, after checks pass | `android` | Signed universal APK + per-ABI APKs (armeabi-v7a, arm64-v8a, x86_64) |
| Same triggers, after checks pass | `macos` → reusable `build-macos.yml` | Universal unsigned macOS DMG + ZIP + SHA-256 checksums from the same commit/profile as Android |
| Push to `main`, push `self-hosted-skydrow` / `build/macos-dmg` / `fix/android-input-settings-device-test`, push a `v*` tag, or set manual `build_web` to `true` | `web` | `duoyi-web-*.tar.gz` for desktop/mobile from the same commit/profile; branch pushes upload the artifact only, except the `main` desktop tarball which auto-deploys once the server entry and single Secret are configured; Pages stays `main`-only |
| Tag `v*` push, after Android/Web/macOS succeed | `release` | Auto-creates GitHub Release with APKs, AAB, web tarballs and macOS packages |

Each push to the four build branches must enter the main `build` workflow so Android and macOS cannot drift onto different commits. The reusable macOS workflow has no separate push trigger; keep its manual entry. Manual main runs default `build_macos` to true and can explicitly skip it. Ordinary branch pushes upload Actions artifacts without creating a Release (the `main` desktop Web tarball also auto-deploys once the server entry and single Secret are configured); newer pushes cancel unfinished runs on the same branch. Guard changes to these triggers/dependencies with `test/services/multi_platform_build_workflow_static_test.dart`.

Mainline integration follows `docs/mainline-integration.md`: verify the candidate contains every intended local/origin head, the approved Logo reference and generator checks, and the main-only deployment job. Keep unrelated worktrees and uncommitted files intact.

### Required Repository Secrets

- `DUOYI_KEYSTORE_BASE64`: Base64-encoded Android keystore (release build fails without it — no debug-signing fallback)
- `DUOYI_KEYSTORE_PASSWORD`, `DUOYI_KEY_ALIAS`, `DUOYI_KEY_PASSWORD`

### Optional Repository Variables

- Public deployment values are maintained in `config/deployment.json`; repository variables can override backend URL, update repository, and Web base href. The manual `same_origin` input explicitly selects an empty backend URL.

### Creating a Release

1. Bump the version in **both** `pubspec.yaml` and `lib/core/app_version.dart`
2. Tag and push:

```bash
git tag v1.1.38
git push origin v1.1.38
```

GitHub Actions attaches the universal APK, per-ABI APKs, AAB, web tarballs, macOS DMG/ZIP and `SHA256SUMS-macos.txt` to the Release. The app checks for updates via "我的 → 检查更新" by querying the GitHub Releases API.

Download pages in `deploy/duoyi.html` and `deploy/duoyi-test-cases.html` are updated and published alongside releases (see `docs: publish ... download pages` commits).

## Server URL Configuration

Installed clients persist a runtime server URL and authenticate with an access token; password/email login remains available. Web defaults to same-origin `/api/*` and `/ws/*`, regardless of the profile's installed-client URL.

- Deployment values live in `config/deployment.json`; `DUOYI_SERVER_URL` supplies the installed client's initial URL.
- Use `python3 scripts/flutter_with_config.py ...` to validate and inject public build defaults.
- `AuthProvider` owns the active URL and Bearer credential. Use its client/getters for API, AI, sync, sharing, WebSockets and backend update policy.
- Stored credentials and account data are bound to server + account. Verify token login before replacing a connection and run account cleanup before applying a different server/account.
- Create/revoke named, optionally expiring tokens in Profile → Access tokens. Full secrets are returned only once; the backend stores hashes. Never include them in profiles or Dart defines.

## Key Features

### AI Integration

- Compatible with OpenAI `chat/completions` API (any OpenAI-compatible gateway works)
- Managed via admin panel (Base URL, API Key, model selection, daily usage limits)
- **AI Task Breakdown**: Converts single-line task description into structured subtasks
- **AI Weekly Review**: Generates summary and suggestions based on completed tasks
- Rate limiting: per-user daily quota enforced in backend

### Admin Panel

Accessible in-app via "我的 → 管理员后台" (admin users only). Tabs cover: overview KPIs, site settings (registration/invite code/maintenance mode), AI config, cloud backup, user management, announcements, feedback, and invite codes.

## Testing Strategy

- Flutter tests live under `test/{core,models,providers,screens,services,widgets}/` (~380 files); shared helpers in `test/test_support/`
- `*_static_test.dart` files are source-scanning convention guards (see Critical Conventions above)
- Integration smoke test: `integration_test/app_alignment_smoke_test.dart`
- Backend API tests: `backend/test_workspaces.py`; discover `backend/test_*.py` to include access-token, config and Web build-policy tests (unittest-style).
- CI runs Flutter and Python tests on every push/PR; `scripts/alignment_regression_gate.sh` is the heavier pre-release gate

## Deployment Notes

### Production Backend

- Runner, service/container name, public URL and local health URL come from the deployment profile.
- `scripts/deploy_backend_prod.sh --check-config` only validates targets. A normal invocation restarts the selected Docker/systemd runner and verifies API contracts.
- Docker deployments must rebuild the image with all backend modules and version metadata, then recreate the container to apply image or Compose env_file changes. A restart alone preserves the original image/environment; GitHub client Releases do not deploy backend code.
- Preserve the configured SQLite/data directories and password salt across upgrades; no database reset is needed.

### Web Client

Only a `main` push publishes the same-run desktop Web artifact through `deploy-self-hosted-web`, `scripts/deploy_web_ci.py` and the restricted `/usr/local/sbin/duoyi-web-deploy` entry. The checked-in public profile and pinned host key, archive/commit verification, atomic symlink switch and rollback remain required. Production Web publication does not change backend/DB/Nginx or credentials; tags and other branches do not publish it. See `docs/web-auto-deploy.md`.

Use the shared build entrypoint for same-origin deployment:

```bash
python3 scripts/flutter_with_config.py build web --release --dart-define=DUOYI_SERVER_URL=
```

Nginx config example:
```nginx
location /api/ { proxy_pass http://127.0.0.1:8000; }
location /ws/ { proxy_pass http://127.0.0.1:8000; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
location / { try_files $uri $uri/ /index.html; }
```

## Localization

- Uses Flutter's built-in l10n (`flutter_localizations`); config in `l10n.yaml`
- Template ARB is **Chinese** (`lib/l10n/app_zh.arb`); supported locales: zh (primary), en
- Generated files: `lib/l10n/generated/`
- Custom wrapper: `lib/core/i18n.dart` with `I18n.tr()` helper; several static guard tests enforce i18n usage in screens
- Language defaults to the system locale; a persisted explicit choice (`system` / `zh` / `en`) lives in `LocaleProvider` and applies immediately (`lib/widgets/language_settings_tile.dart`; also "扩展 → 语言")

## Time Model

- `AppClock` (`lib/core/app_clock.dart`) is the single source for user-visible wall-clock time: `now()`, `date()`, `dateOnly()`, `today()`, `watch()`, `notifyDayChanged()`. "Today", day grouping, per-day stats, habit periods, almanac and date formatting must use it.
- The application time zone comes from `LocalTimezoneResolver` (`lib/core/local_timezone_resolver.dart`): system zone by default, user-overridable IANA zone persisted by `PreferencesProvider` (`setAppTimeZone` / `refreshResolvedTimeZone`). Reminders are replayed on zone change and on resume.
- Keep real instants for cloud-sync timestamps, `updatedAt`, IDs and elapsed timers. Floating date-only values (todo `date`, anniversaries) keep their stored year/month/day and never shift across zones.
- Full rules and verification checklist: `docs/configuration.md` → 语言与应用时区.

## Platform-Specific Features

### Linux Desktop
- System tray integration (see `lib/services/system_tray.dart`)
- DBus desktop notifications

### Android
- Home screen widgets (todo/habit/pomodoro 3-column layout)
- Deep links via `duoyi://` scheme
- Notifications via `flutter_local_notifications`

### Web
- PWA manifest in `web/manifest.json`
- WebSocket support for real-time features (focus rooms)
