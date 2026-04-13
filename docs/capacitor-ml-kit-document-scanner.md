# Capacitor + ML Kit Document Scanner

This repo can use Google ML Kit Document Scanner through a Capacitor Android shell.

The shell workspace now lives at:

- `mobile/app`

What the web app expects:

- `Scan` keeps the current browser overlay for normal web/PWA usage
- `Scan` hands off to a native Android document scanner when the app is running inside Capacitor and the plugin is available
- the native scanner should return:
  - a preview image as `data:image/...;base64,...`
  - a PDF as `data:application/pdf;base64,...`

## Native plugin contract

A scaffolded local Capacitor plugin package now lives at:

- `mobile/plugins/inkcreate-document-scanner`

That package gives you:

- a reusable Capacitor plugin name of `InkcreateDocumentScanner`
- the Android ML Kit bridge in Kotlin
- a small JS package entrypoint for the Capacitor shell to install locally

The web layer looks for one of these plugin handles:

- `window.InkcreateDocumentScanner`
- `window.Capacitor.Plugins.InkcreateDocumentScanner`
- `window.Capacitor.Plugins.NativeDocumentScanner`

The plugin may expose any one of:

- `scanDocument(options)`
- `startScan(options)`
- `openScanner(options)`

The web app currently calls the plugin with:

```json
{
  "formats": ["jpeg", "pdf"],
  "pageLimit": 24,
  "allowGalleryImport": true,
  "scannerMode": "full"
}
```

Expected result shape:

```json
{
  "title": "Scan — Apr 13, 2026 22:10:04",
  "previewImageDataUrl": "data:image/jpeg;base64,...",
  "pdfDataUrl": "data:application/pdf;base64,...",
  "pages": [
    {
      "imageDataUrl": "data:image/jpeg;base64,..."
    }
  ]
}
```

Notes:

- `previewImageDataUrl` is preferred for the scanned-document thumbnail.
- `pdfDataUrl` is preferred so Inkcreate stores the native multi-page PDF directly.
- If only page images are returned, Inkcreate can still save the scan, but it will fall back to generating a PDF from the preview image.
- Cancellation should either return `{ "cancelled": true }` or throw an error/message containing `cancel`.

## Rails payload

The scanned-document create endpoints now accept:

```json
{
  "scanned_document": {
    "title": "Receipt",
    "enhancement_filter": "auto",
    "tags": "[]",
    "image_data": "data:image/jpeg;base64,...",
    "pdf_data": "data:application/pdf;base64,..."
  }
}
```

That works for:

- immediate save on page/notepad scanned-document sections
- pending draft scanned documents on new page / new notepad forms

## Product fit

This is the right Android-native capture path when you want:

- Google’s document-boundary detection
- Google’s native scan UI
- multi-page PDF output

This does not replace the browser scanner for web/PWA users, and it does not provide iOS support by itself because ML Kit Document Scanner is Android-only.

## Shell workflow

From the repo root:

```bash
cd mobile/app
npm install
export INKCREATE_APP_URL=http://10.0.2.2:3000
npx cap add android
npx cap sync android
npx cap open android
```

Notes:

- `http://10.0.2.2:3000` is the Android emulator alias for a Rails server running on your Mac at `localhost:3000`.
- For a physical device, use a LAN-accessible or deployed HTTPS URL instead.
- The shell already links the local plugin package at `../plugins/inkcreate-document-scanner`.
