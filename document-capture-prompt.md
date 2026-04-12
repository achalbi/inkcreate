# Prompt — Build a Document Capture & OCR Feature for InkCreate

> Copy the section below and paste it into Claude (or any capable LLM) to generate the feature. Attach `daily-note-light.html` for style-matching.

---

## Important: Where This Feature Lives

This is a **new feature** called **Document Capture** that fits into the InkCreate app ecosystem alongside the existing features.

| Feature | Scope | Description |
|---|---|---|
| Voice Notes | Page-level | Audio recordings on a daily page |
| Todos | Page-level | Quick checkboxes on a daily page |
| Tasks | App-level | Long-lived work items (separate feature) |
| Photo Gallery | Page-level | Photos attached to a daily page |
| **Document Capture** (to build) | **Page-level + App-level** | Capture a physical document via camera, auto-detect edges, crop/enhance, and extract text via OCR |

Document Capture can be triggered from:
1. A daily page (captured document + extracted text are saved to that page)
2. A standalone "Scan" quick-action from the bottom nav FAB or home screen (user picks which page/notebook to save to afterward)

---

## The Prompt

Build a **Document Capture & OCR feature** for my **InkCreate** note-taking application. This lets users photograph physical documents, automatically detect and crop the document boundaries using **OpenCV.js**, apply image enhancement, and extract the text using **Tesseract.js** — with the architecture designed so Tesseract can be swapped for **Google ML Kit / Cloud Vision API** in the future without touching the UI layer.

Deliver it as a single-file, interactive HTML prototype that matches my existing design language (cream/beige light theme, warm orange-red accent `#ff5f4e`, Inter font, 22px card radii, subtle dotted background). All state in-memory (no localStorage).

### Context you should assume
- The app is a daily notepad: **Page** inside a **Chapter** inside a **Notebook**.
- Pages already have voice notes, page-level todos, and a photo gallery.
- Document Capture is a new section on the daily page AND a standalone quick-action.
- The captured document image goes into the page's photo gallery (or a new "Documents" section).
- The extracted text is stored alongside the image and is searchable / copyable / editable.

---

### Architecture — the OCR abstraction layer

This is critical for future-proofing. Build an **OCR Engine abstraction** so Tesseract.js can be swapped for Google ML Kit (or any other provider) without changing the UI or capture pipeline.

```ts
// ── OCR Engine Interface ──────────────────────────
interface OCREngine {
  name: string                          // "tesseract" | "google-ml" | "cloud-vision"
  initialize(): Promise<void>
  recognize(image: ImageData | Blob | HTMLCanvasElement, options?: OCROptions): Promise<OCRResult>
  terminate(): Promise<void>
  isReady(): boolean
  getSupportedLanguages(): string[]
}

interface OCROptions {
  language?: string                     // "eng", "fra", "deu", etc.
  mode?: 'fast' | 'accurate'           // trade speed vs accuracy
  regions?: CropRegion[]               // specific regions to OCR (skip the rest)
  outputFormat?: 'plain' | 'hocr' | 'structured'
}

interface OCRResult {
  text: string                          // full extracted text
  confidence: number                    // 0–100
  blocks: TextBlock[]                   // structured output
  processingTimeMs: number
  engine: string                        // which engine was used
}

interface TextBlock {
  text: string
  confidence: number
  bbox: { x: number; y: number; w: number; h: number }
  lines: TextLine[]
}

interface TextLine {
  text: string
  confidence: number
  bbox: { x: number; y: number; w: number; h: number }
  words: TextWord[]
}

interface TextWord {
  text: string
  confidence: number
  bbox: { x: number; y: number; w: number; h: number }
}

// ── Tesseract.js Implementation ───────────────────
class TesseractEngine implements OCREngine {
  name = 'tesseract'
  private worker: Tesseract.Worker | null = null
  // ... implement all methods using tesseract.js
}

// ── Future: Google ML Kit Implementation ──────────
class GoogleMLEngine implements OCREngine {
  name = 'google-ml'
  // ... implement using @anthropic-ai/google-ml-kit or REST API
}

// ── Engine Factory ────────────────────────────────
class OCREngineFactory {
  static create(provider: 'tesseract' | 'google-ml' | 'cloud-vision'): OCREngine {
    switch (provider) {
      case 'tesseract': return new TesseractEngine()
      case 'google-ml': return new GoogleMLEngine()
      default: return new TesseractEngine()  // fallback
    }
  }
}

// ── Usage ─────────────────────────────────────────
const engine = OCREngineFactory.create(appConfig.ocrProvider) // swap in settings
await engine.initialize()
const result = await engine.recognize(croppedCanvas, { language: 'eng', mode: 'accurate' })
```

For the prototype, only implement `TesseractEngine`. Stub out `GoogleMLEngine` with a placeholder that returns mock data. Add a toggle in the UI to switch between them (the toggle should visually exist and swap the engine reference, even if Google ML is stubbed).

---

### Pipeline — the 5-stage document capture flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ 1. Capture│───▶│ 2. Detect│───▶│ 3. Crop &│───▶│ 4. OCR   │───▶│ 5. Review│
│   (camera)│    │  (edges) │    │  Enhance │    │  (text)  │    │  & Save  │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
```

Each stage is a distinct screen/step in the UI with its own clear affordances.

---

### Stage 1 — Camera Capture

**What it does:** Open the device camera, show a live viewfinder, let the user take a photo of a document.

**UI:**
- Full-screen camera viewfinder (using `getUserMedia` API).
- Semi-transparent overlay frame showing the ideal document placement zone.
- Auto-detect mode: as the user holds the camera, OpenCV runs real-time edge detection on the video frames and draws a **green quadrilateral outline** around any detected document.
- Status text at top: "Align document within the frame" → changes to "Document detected!" (green) when edges are found.
- Capture button (large, circular, center-bottom — like a camera shutter).
- Option to pick from gallery instead (small icon button: "📁 Gallery").
- Flash toggle (if device supports it).
- Back/cancel button.

**OpenCV.js usage for real-time detection:**
```
1. Capture video frame → convert to grayscale
2. Apply GaussianBlur to reduce noise
3. Canny edge detection
4. findContours → filter by area (>30% of frame) and approxPolyDP (4 corners = rectangle)
5. Draw the largest valid quadrilateral on the overlay canvas
6. When stable for 500ms+ → auto-capture OR wait for manual tap
```

**Settings:**
- Auto-capture on/off (default: on — captures automatically when a stable document is detected for 1s)
- Resolution preference: low / medium / high

---

### Stage 2 — Edge Detection & Corner Adjustment

**What it does:** Show the captured image with the detected document corners highlighted. Let the user manually adjust corners if the auto-detect was slightly off.

**UI:**
- Full-screen image with a **draggable 4-corner overlay**.
- Each corner is a large touch-friendly handle (32px circle with a glow).
- Connecting lines between corners drawn as a bright quadrilateral.
- "Magnifier loupe" when dragging a corner — shows a zoomed-in circle at the touch point for precision.
- Buttons at bottom: "↺ Retake" / "✓ Crop".
- If OpenCV detected no document: show all 4 corners at image edges and prompt "Drag corners to select the document area."

**OpenCV.js processing:**
```
1. Take the captured image
2. Run the same contour detection pipeline
3. Find the best quadrilateral (or default to full image)
4. Expose 4 corner points as draggable handles
5. On "Crop" → apply perspectiveTransform (4-point warp) to produce a flat, rectangular output
```

---

### Stage 3 — Image Enhancement

**What it does:** After perspective correction, apply enhancement filters to make the document scan look clean and professional.

**UI:**
- Preview of the cropped, perspective-corrected image.
- Filter strip (horizontal scroll) with live previews:
  - **Original** — no changes
  - **Auto-enhance** — adaptive thresholding + contrast (default, auto-selected)
  - **Grayscale** — simple desaturation
  - **B&W Document** — aggressive binarization for high-contrast text
  - **Color boost** — increased saturation + sharpening for colorful documents
  - **Lighten** — brighten shadows (for poorly lit scans)
- Brightness / Contrast sliders (collapsible "Manual adjust" panel).
- Rotation buttons: 90° left, 90° right, flip.
- Buttons at bottom: "← Back" / "Extract text →"

**OpenCV.js processing:**
```
- Auto-enhance: convertToGray → adaptiveThreshold → convertBack
- B&W Document: threshold(THRESH_BINARY + THRESH_OTSU)
- Color boost: convertToHSV → increase S channel → convertBack → sharpen
- Brightness/Contrast: convertScaleAbs(alpha, beta)
- Rotation: getRotationMatrix2D → warpAffine
```

---

### Stage 4 — OCR Text Extraction

**What it does:** Run the enhanced image through the OCR engine (Tesseract.js by default) and extract text.

**UI:**
- Split view: **image on top** (or left on wide screens), **extracted text below** (or right).
- Loading state while OCR is processing:
  - Progress bar with percentage (Tesseract.js reports progress).
  - Status text: "Initializing engine…" → "Recognizing text… 45%" → "Done!"
  - The document image gets a subtle scanning animation (a horizontal light bar sweeping top-to-bottom).
- Once complete:
  - Confidence meter: "🟢 96% confidence" / "🟡 72% confidence" / "🔴 34% confidence"
  - Extracted text in an editable textarea so the user can fix OCR errors.
  - **Word-level highlighting**: tapping a word in the text highlights the corresponding bounding box on the image. Tapping a region on the image highlights the corresponding text.
  - Language selector dropdown (English, French, German, Spanish, etc.) — changing it re-runs OCR.
  - "Engine" selector: Tesseract.js / Google ML (stubbed) — shows which engine is active.
- Buttons at bottom: "← Re-enhance" / "Save ✓"

**Tesseract.js implementation:**
```js
import Tesseract from 'tesseract.js'

const worker = await Tesseract.createWorker('eng', 1, {
  logger: m => updateProgress(m.progress)  // feed progress to UI
})

const result = await worker.recognize(enhancedCanvas, {
  // return word-level bounding boxes for highlight feature
})

// result.data.text → full text
// result.data.words → word-level with bbox
// result.data.confidence → overall confidence
```

---

### Stage 5 — Review & Save

**What it does:** Final review screen before saving to the app.

**UI:**
- Thumbnail of the scanned document (enhanced version).
- Extracted text preview (first 3 lines + "… see more").
- Metadata: page count (if multi-page), confidence, engine used, timestamp.
- **Save options:**
  - **Save to current page** (default when triggered from a daily page)
  - **Pick a page** — opens the same Notebook → Chapter → Page picker from the Tasks feature
  - **Create new page** — auto-creates a new daily page with today's date and saves there
  - **Save as standalone** — saved to a "Scanned Documents" library at the app level
- **Document title** — editable, defaults to first line of extracted text or "Scan — Apr 11, 2026"
- **Tags** — freeform tags for the document.
- Buttons: "← Back to edit" / "Save ✓"

After saving:
- Return to the page where the document was saved.
- The document appears in a new **"Scanned Documents"** section on the page (or in the Photo Gallery with a scan badge).
- Show a success toast: "Document saved! 📄"

---

### Data model

```ts
// ── Scanned Document ──────────────────────────────
type ScannedDocument = {
  id: string
  title: string
  createdAt: Date

  // Images
  originalImage: Blob              // raw camera capture
  croppedImage: Blob               // after perspective correction
  enhancedImage: Blob              // after filter/enhancement
  enhancementFilter: string        // which filter was applied

  // OCR
  extractedText: string            // user-editable final text
  rawOCRResult: OCRResult          // full structured result from engine
  ocrEngine: string                // "tesseract" | "google-ml"
  ocrLanguage: string              // "eng"
  ocrConfidence: number            // 0–100

  // Location in the app
  savedTo: {
    type: 'page' | 'standalone'
    notebookId?: string
    chapterId?: string
    pageId?: string
  }

  tags: string[]
  metadata: {
    deviceInfo?: string
    resolution?: { w: number; h: number }
    fileSize?: number
  }
}

// ── App Config (for engine selection) ─────────────
type AppConfig = {
  ocrProvider: 'tesseract' | 'google-ml' | 'cloud-vision'
  captureSettings: {
    autoCapture: boolean            // auto-snap when document detected
    resolution: 'low' | 'medium' | 'high'
    defaultFilter: string           // 'auto-enhance' | 'original' | etc.
    defaultLanguage: string         // 'eng'
  }
}
```

---

### How it looks on a daily page (after saving)

New **"Scanned Documents"** section on the daily page, styled identically to Voice Notes:

```
┌─────────────────────────────────────────────────┐
│  📄 Scanned Documents              [1]     ⌄    │
│  ─────────────────────────────────────────────── │
│                                                   │
│  ┌───────────────────────────────────────────┐   │
│  │ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ (accent gradient bar)   │   │
│  │                                             │   │
│  │  📄 Meeting Notes — Apr 11                  │   │
│  │  🟢 96% confidence · Tesseract · 2.4 KB     │   │
│  │                                             │   │
│  │  ┌─────────┐  "The quarterly review showed │   │
│  │  │ 📷 thumb │  strong growth in Q1 with a  │   │
│  │  │         │  17% increase in active…"     │   │
│  │  └─────────┘                                │   │
│  │                                             │   │
│  │  [📋 Copy text] [✏️ Edit] [🔍 View full]  🗑 │   │
│  └───────────────────────────────────────────┘   │
│                                                   │
│  [ + Scan a document ]                            │
└─────────────────────────────────────────────────┘
```

**Card anatomy:**
- Accent gradient top-bar (same as voice note cards)
- Document title
- Confidence badge + engine name + file size
- Side-by-side: thumbnail (left) + text excerpt (right, max 3 lines)
- Action row: Copy text, Edit, View full, Delete

---

### Libraries to use

```html
<!-- OpenCV.js — for edge detection, perspective transform, enhancement -->
<script async src="https://docs.opencv.org/4.x/opencv.js"></script>

<!-- Tesseract.js — for OCR (v5+) -->
<script src="https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js"></script>
```

Both libraries run **entirely in the browser** — no backend required for the prototype.

---

### Multi-page scanning (bonus)

If the user wants to scan a multi-page document:
- After Stage 5, show a "Scan another page" button.
- Each page goes through Stages 1–4 independently.
- Stage 5 shows all pages as a stack with a page navigator.
- Extracted text is concatenated with `--- Page 2 ---` separators.
- Saved as a single `ScannedDocument` with an array of page images.

---

### Settings screen (inside app Settings)

Add a **"Document Capture"** section to the existing Settings screen:

- **OCR Engine:** dropdown — Tesseract.js / Google ML Kit (coming soon)
- **Default language:** dropdown — English, French, German, Spanish, Hindi, Japanese, Chinese, Korean, Arabic
- **Auto-capture:** toggle (default: on)
- **Default filter:** dropdown — Auto-enhance / Original / B&W Document / Grayscale
- **Camera resolution:** Low (fast) / Medium (balanced) / High (best quality)
- **Save location:** Current page / Always ask / Scanned Documents library

---

### Visual style (must match existing app)

- **Background:** `#faf6ef` with subtle dotted pattern
- **Cards:** `#fffaf1` surface, 1px border, 22px radius
- **Accent:** `#ff5f4e` (capture button, progress bar, active states)
- **Confidence colors:** `#2eaa60` (high ≥80%) · `#e0a92a` (medium 50–79%) · `#e4534a` (low <50%)
- **Font:** Inter 400/500/600/700
- **Camera UI:** Dark overlay (`rgba(0,0,0,0.7)`) with bright accent elements for contrast
- **Enhancement filters strip:** Horizontal scroll with rounded preview thumbnails
- **Motion:** Same spring curves as the rest of the app

### Micro-interactions
- Shutter button: scale-down on press, spring-back on release, flash overlay on capture.
- Corner drag handles: glow + slight scale-up when grabbed.
- Filter selection: selected filter thumbnail gets an accent ring + check mark.
- OCR scanning animation: horizontal light bar sweeping over the document.
- Confidence meter: animated fill with color transition.
- Save success: confetti-like particle burst from the save button.

### Accessibility
- Camera viewfinder has `aria-live` region announcing detection status.
- All adjustment handles are keyboard-accessible (arrow keys to nudge).
- Filter strip is navigable with left/right arrow keys.
- OCR progress is announced via `aria-live`.
- Text contrast ≥ 4.5:1 in all states (including the dark camera overlay).

---

### Deliverable

One self-contained `document-capture.html` file with HTML + CSS + vanilla JS that includes:
- All 5 stages as navigable screens within the file.
- Real OpenCV.js edge detection (loads the library from CDN).
- Real Tesseract.js OCR (loads from CDN) — processing a sample image or user-uploaded file.
- Stubbed Google ML engine (returns mock data, switchable in UI).
- Camera viewfinder using `getUserMedia` (falls back to file upload on desktop).
- 3 sample pre-loaded document images for testing without a camera.
- The daily-page "Scanned Documents" section showing saved results.
- A working settings panel for engine/language/filter preferences.

### Out of scope (v1)
- Real backend / cloud storage
- PDF export of scanned documents
- Handwriting recognition (beyond what Tesseract can do)
- Batch scanning from gallery (multi-select)
- Offline language pack management
- Real Google ML Kit integration (just the stub)

### Acceptance criteria
- [ ] Camera opens and shows live viewfinder with document detection overlay.
- [ ] Green outline appears when a document is detected via OpenCV.js.
- [ ] Auto-capture triggers after ~1s of stable detection (or manual tap works).
- [ ] Corner adjustment handles are draggable and perspective correction works.
- [ ] All 5 enhancement filters produce visibly different results.
- [ ] Tesseract.js successfully extracts text with progress reporting.
- [ ] Confidence meter accurately reflects OCR quality.
- [ ] Word-level highlighting works (tap word ↔ highlight on image).
- [ ] Document saves to a page and appears in the Scanned Documents section.
- [ ] OCR engine can be toggled between Tesseract and the Google ML stub.
- [ ] Multi-page scanning flow works for at least 2 pages.
- [ ] Visual style matches the existing `daily-note-light.html` theme.
- [ ] Works on both mobile (camera) and desktop (file upload fallback).

---

### Future roadmap (do not build now, but design the architecture to support)

1. **Google ML Kit integration** — replace Tesseract with on-device ML for faster, more accurate recognition. The `OCREngine` interface is already designed for this.
2. **Cloud Vision API** — optional cloud-based OCR for complex documents (tables, forms, handwriting). Add as another engine implementation.
3. **PDF export** — convert scanned documents to searchable PDFs (text layer + image).
4. **Form field detection** — identify and extract key-value pairs from structured forms.
5. **Table extraction** — detect tables in documents and convert to structured data (CSV/spreadsheet).
6. **Handwriting recognition** — specialized model for handwritten notes.
7. **Language auto-detection** — automatically detect the document language before OCR.
8. **Batch scanning** — select multiple photos from gallery and process them all.
9. **Smart search** — search across all extracted text from all scanned documents in the app.

---

## How to use this prompt

1. Paste everything between `## The Prompt` and the final `---` into a fresh Claude conversation.
2. Attach `daily-note-light.html` for exact style matching.
3. Note: OpenCV.js is ~8MB — the prototype will take a moment to load.
4. Test on mobile for the full camera experience; desktop will use file-upload fallback.
5. Iterate: *"improve the edge detection accuracy"*, *"add table extraction"*, *"swap in Google ML Kit"*.
