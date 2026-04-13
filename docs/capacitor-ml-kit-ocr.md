# Capacitor + ML Kit OCR

This repo is still a server-rendered Rails PWA, so the clean native OCR split is:

- web/PWA keeps `Capture -> Detect -> Enhance -> Save PDF`
- native mobile shell runs OCR only when the user taps `Run OCR` on a saved scanned document
- the OCR result is posted back into the existing `ScannedDocument` record

## Why this shape

Each `ScannedDocument` already stores:

- `enhanced_image`
- `document_pdf`
- `extracted_text`
- `ocr_engine`
- `ocr_language`
- `ocr_confidence`

ML Kit should read `enhanced_image`, not the generated PDF.

## Web bridge contract

When the app is running inside Capacitor, the scanned document OCR button looks for one of these plugin handles:

- `window.InkcreateNativeOcr`
- `window.Capacitor.Plugins.InkcreateNativeOcr`
- `window.Capacitor.Plugins.NativeTextRecognition`

The plugin should expose either:

- `recognizeText(payload)`
- `runOcr(payload)`

Payload sent from the web app:

```json
{
  "imageDataUrl": "data:image/jpeg;base64,...",
  "documentId": "uuid",
  "title": "Receipt"
}
```

Expected plugin response:

```json
{
  "text": "Total: 42.00",
  "confidence": 0.92,
  "language": "eng",
  "engine": "google-ml"
}
```

Notes:

- `confidence` may be `0..1` or `0..100`; the Rails app normalizes either form.
- `engine` should be `google-ml` for ML Kit OCR results.

## Rails endpoints

Page-owned scanned documents:

- `POST /notebooks/:notebook_id/chapters/:chapter_id/pages/:page_id/scanned_documents/:id/submit_ocr_result`
- `GET /notebooks/:notebook_id/chapters/:chapter_id/pages/:page_id/scanned_documents/:id/ocr_source`

Notepad-owned scanned documents:

- `POST /notepad/:notepad_entry_id/scanned_documents/:id/submit_ocr_result`
- `GET /notepad/:notepad_entry_id/scanned_documents/:id/ocr_source`

Expected request body:

```json
{
  "ocr_result": {
    "text": "Total: 42.00",
    "confidence": 92,
    "language": "eng",
    "engine": "google-ml"
  }
}
```

Expected OCR source response:

```json
{
  "ok": true,
  "image_data_url": "data:image/jpeg;base64,..."
}
```

## Recommended mobile workspace

Because the Rails app is server-rendered and does not ship as a bundled SPA, the recommended approach is the separate `mobile/app` Capacitor workspace rather than retrofitting Capacitor into the Rails root.

That mobile shell should:

- host the existing Inkcreate app in a Capacitor WebView
- register the native OCR plugin above
- use ML Kit Text Recognition on Android and iOS
- return recognized text back to the web layer through the plugin bridge
