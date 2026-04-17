# InkCreate Flutter Shell

This workspace hosts a Flutter mobile shell around the existing InkCreate Rails web app.

Why `mobile/flutter_shell/` instead of `mobile/` root:

- `mobile/app/` and `mobile/plugins/` already contain an older Capacitor shell and native plugin experiments.
- Preserving that history avoids destructive rewrites while making the Flutter shell the forward path.

## Architecture

- The primary product UI stays in a WebView pointed at the Rails app.
- Native capability discovery is exposed to the web app through a single bridge contract.
- Device-heavy and ML-heavy features run in native Flutter routes or Android/iOS platform channels.
- Unsupported native routes always return structured `unavailable` results.

## Current real integration

- The first production workflow is the existing scanned-documents flow used from page and notepad screens in the Rails app.
- The web layer now loads `/scripts/inkcreate_native_bridge.js` and opens `mlkit:document-scanner` through `window.InkCreateNative`.
- Android document scanning uses the Google ML Kit scanner and returns native multi-page images/PDF plus OCR analysis for immediate downstream language detection.
- iOS document scanning uses VisionKit as the graceful fallback scanner and returns multi-page images/PDF to the same web workflow.

## Capability routes

- Cross-platform: `mlkit:text-recognition-v2`, `mlkit:barcode-scanning`, `mlkit:language-identification`, `mlkit:translation`, `mlkit:entity-extraction`
- Android-first: `mlkit:document-scanner`
- Android-only GenAI: `genai:speech-recognition`, `genai:summarization`, `genai:prompt`

## Debug host URL selection

- Release builds use `https://inkcreate.thoughtbasics.com`
- Debug builds default to:
  - Android emulator: `http://10.0.2.2:3000`
  - Android physical device: `http://127.0.0.1:3000`
  - iOS simulator/macOS: `http://localhost:3000`
- Physical Android debug runs expect `adb reverse tcp:3000 tcp:3000` so device localhost maps back to the Rails dev server on your Mac.
- `tool/run_android_debug.sh` auto-detects a local dev server on `8080` or `3000`, sets the matching `INKCREATE_DEBUG_BASE_URL`, and forwards the same port with `adb reverse`.
- You can force a specific local port with `INKCREATE_DEBUG_PORT=8080`, or override the full host with `INKCREATE_DEBUG_BASE_URL=...`.
- Override with `--dart-define=INKCREATE_DEBUG_BASE_URL=https://your-host`

## Platform notes

- Android GenAI support is capability-gated at runtime and relies on AICore / Gemini Nano readiness.
- iOS gracefully reports Android-only GenAI routes as unavailable.
- Android minSdk is pinned to `26`.
- Debug Android builds allow cleartext traffic so emulator traffic can reach `http://10.0.2.2:3000`.
- iOS includes camera and photo-library privacy strings for scanner/OCR flows.

## Getting started

1. Install Flutter stable and the normal Android/iOS toolchains.
2. From `mobile/flutter_shell`, run `flutter pub get`.
3. Start the Rails app from the repo root with `bin/dev`.
4. Run the shell with `flutter run -d android` or `flutter run -d ios`.
5. For a physical Android device, run `./tool/run_android_debug.sh [device-id]` to set up `adb reverse` and launch Flutter with the inferred localhost debug host.
6. Override the debug web host if needed with `--dart-define=INKCREATE_DEBUG_BASE_URL=...`.

## Common commands

Start the Rails app from the repo root:

```bash
cd /Users/achalindiresh/workspace/inkcreate
bin/dev
```

Install Flutter dependencies:

```bash
cd /Users/achalindiresh/workspace/inkcreate/mobile/flutter_shell
flutter pub get
```

Run on a physical Android device using the local Rails server.
This auto-detects `8080` or `3000`, sets `adb reverse`, and launches Flutter:

```bash
cd /Users/achalindiresh/workspace/inkcreate/mobile/flutter_shell/tool
sh run_android_debug.sh
```

Run on a specific physical Android device:

```bash
cd /Users/achalindiresh/workspace/inkcreate/mobile/flutter_shell/tool
sh run_android_debug.sh WSYHNVMBDAJJ6PNR
```

Force a specific local Rails port:

```bash
cd /Users/achalindiresh/workspace/inkcreate/mobile/flutter_shell/tool
INKCREATE_DEBUG_PORT=8080 sh run_android_debug.sh
```

Run against production instead of local Rails:

```bash
cd /Users/achalindiresh/workspace/inkcreate/mobile/flutter_shell/tool
INKCREATE_DEBUG_BASE_URL=https://inkcreate.thoughtbasics.com sh run_android_debug.sh
```

Run on an Android emulator:

```bash
cd /Users/achalindiresh/workspace/inkcreate/mobile/flutter_shell
flutter run -d android
```

Run on iOS:

```bash
cd /Users/achalindiresh/workspace/inkcreate/mobile/flutter_shell
flutter run -d ios
```

## Verification status

- Dart files were formatted locally with the downloaded Dart SDK.
- A full `flutter pub get`, `flutter analyze`, Android build, iOS build, and device runtime test were not completed in this environment because the local Flutter/Xcode/Java toolchain was not fully available.
