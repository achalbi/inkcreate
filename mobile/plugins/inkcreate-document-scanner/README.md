# Inkcreate Capacitor Document Scanner

Local Capacitor plugin scaffold for Android document capture using Google ML Kit Document Scanner.

This plugin matches the web contract already used by Inkcreate in:

- `/public/scripts/controllers/document_capture_controller.js`
- `/docs/capacitor-ml-kit-document-scanner.md`

## What it does

- opens Google's native Android document-scanner flow
- returns a preview JPEG as a data URL
- returns the generated PDF as a data URL
- keeps the method names flexible for the existing web bridge:
  - `scanDocument(...)`
  - `startScan(...)`
  - `openScanner(...)`

## Why this shape

Inkcreate is still a server-rendered Rails PWA. The web app already knows how to save:

- `scanned_document[image_data]`
- `scanned_document[pdf_data]`

So the native plugin only needs to hand those assets back to the web layer.

## Android notes

- ML Kit Document Scanner is Android-only.
- Google's docs say the scanner UI is delivered by Google Play services.
- Google's docs also say your app does not need its own camera permission for this flow.
- Minimum Android API is `21`.

## Plugin path

Kotlin source:

- `android/src/main/java/com/inkcreate/plugins/documentscanner/InkcreateDocumentScannerPlugin.kt`

Android dependency:

- `com.google.android.gms:play-services-mlkit-document-scanner:16.0.0`

## Expected JS usage

```js
import InkcreateDocumentScanner from "@inkcreate/capacitor-document-scanner";

const result = await InkcreateDocumentScanner.scanDocument({
  formats: ["jpeg", "pdf"],
  pageLimit: 24,
  allowGalleryImport: true,
  scannerMode: "full",
  title: "Scan"
});
```

Expected response shape:

```json
{
  "title": "Scan - Apr 13, 2026 23:11:42",
  "previewImageDataUrl": "data:image/jpeg;base64,...",
  "pdfDataUrl": "data:application/pdf;base64,...",
  "pageCount": 2,
  "pages": [
    {
      "pageIndex": 0,
      "imageDataUrl": "data:image/jpeg;base64,..."
    }
  ]
}
```

## Integrating into a Capacitor shell

In the separate mobile shell workspace:

1. Add this local package to the app.
2. Run `npx cap sync android`.
3. Host the existing Inkcreate app in the Capacitor WebView.
4. Let the web layer call `window.Capacitor.Plugins.InkcreateDocumentScanner`.

If you want this repo to also contain the full Android shell, add a dedicated `mobile/app/` Capacitor project next and install this plugin there.
