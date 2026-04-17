# Inkcreate — App Features & User Guide

Inkcreate is a **notebook-first capture workspace** built for people who think on paper. It bridges the gap between handwritten notes and digital organisation by combining camera-based capture, background OCR, structured notebooks, and Google Drive export into one seamless workflow.

---

## Core Concepts

### Notebooks
Organise your work the same way you do on paper. A **Notebook** is a top-level container — think of it as a physical binder. Inside each notebook you create **Chapters**, and inside chapters you create **Pages**. Pages hold everything: scanned documents, voice notes, todo lists, and photos.

- Create as many notebooks as you need (work projects, study subjects, personal journals)
- Archive a notebook when a project ends — it stays searchable but out of your active view
- Pages carry a captured date so you always know when the work happened

### Notepad
The **Notepad** is your fast-capture inbox. Unlike notebooks (which are project-structured), notepad entries are organised by date — perfect for daily stand-up notes, quick ideas, meeting minutes, or anything you need to jot down before it disappears.

### Capture Studio
The **Capture Studio** is a mobile-optimised camera interface built specifically for taking page photos. It handles the messy reality of real-world capture: angled shots, shadowed edges, mid-session uploads. The upload flow requests a signed URL and pushes the image directly to cloud storage so the UI stays fast even when you are working through a pile of pages.

---

## Features by Area

### Scanning & OCR
- **Scanned Documents** — Attach high-quality scans to any notebook page or notepad entry. Three capture quality presets (Optimised, High, Original) let you trade file size for fidelity depending on the content.
- **Background OCR** — Text extraction runs as an async background job so your workflow is never blocked waiting for results. OCR results are attached to the capture and become searchable immediately.
- **Manual reprocessing** — Trigger re-extraction on any capture if the first attempt produced poor results.
- **OCR source viewer** — Inspect the exact image that was sent to the OCR engine to diagnose quality issues.

### Voice Notes
Record voice notes directly from a notebook page or notepad entry. A built-in player lets you play back the recording in-app. Transcripts can be submitted manually after recording.

### Todo Lists
Every notebook page and notepad entry can have its own **Todo list**. Items can be checked off, reordered by drag-and-drop, and promoted to the global task tracker with a single action.

### Tasks
The **Tasks** section is a global to-do system that sits across all your notebooks and projects. Tasks can be created directly, extracted from captures via AI summary, or promoted from inline todo lists. Sub-tasks are supported for breaking down larger items.

### Reminders
Set time-based reminders tied to any task or entry. Reminders appear in the **Reminders** dashboard and can be dismissed or snoozed. Push notifications are supported on devices that have been set up through the Devices settings.

### Projects
**Projects** provide a cross-notebook way to group captures. A capture can belong to a project, a notebook page, a daily log — or all three. Use projects when your work doesn't fit neatly into a single notebook (e.g. a client engagement that spans multiple physical notebooks).

### Daily Logs
The **Daily Logs** view shows all captures and entries grouped by calendar date. It is the quickest way to see everything that happened on a given day across all notebooks and notepad entries.

### Library
The **Library** is a flat, chronological view of every capture in your workspace. Filter by status, search by extracted text, and browse without needing to know which notebook something lives in.

### Search
Full-text search runs across all extracted text, titles, and tags. Results link directly back to the page, notepad entry, or capture where the match lives.

---

## Organisation Tools

### Tags
Apply tags to captures to create horizontal groupings that cut across notebooks and projects. Search and filter by tag in the Library and Search views.

### Archive
Notebooks can be archived when a project completes. Archived notebooks are excluded from the active view but remain searchable and can be unarchived at any time.

### Chapters with Move & Restore
Chapters inside a notebook can be reordered or moved to a different notebook. Deleted chapters can be recovered if the privacy setting for recoverable deletions is enabled.

---

## Google Drive Integration

Connect your Google Drive account from **Settings → Backup** to enable automatic export of processed captures. Once connected:

- Captures are synced to a designated Drive folder after OCR completes
- Photos can optionally be included in the backup
- Disconnect at any time — metadata can be cleared on disconnect to keep your Drive tidy

---

## PWA & Offline Support

Inkcreate is a **Progressive Web App** — install it on your phone or desktop from the browser and it behaves like a native app:

- Add to Home Screen on iOS/Android for a full-screen, icon-based launch
- A service worker caches core assets for faster subsequent loads
- Push notifications are available once a device is registered

---

## Settings

| Setting | What it controls |
|---|---|
| OCR mode | Manual — trigger extraction on demand |
| Capture quality | Optimised / High / Original — controls image dimensions and compression |
| Backup | Google Drive sync on/off, folder selection |
| Privacy | OCR processing consent, photo backup consent, recoverable deletions, metadata on disconnect |
| Workspace launcher | Idle timeout before the launcher overlay appears |
| Devices | View and remove registered devices, enable/disable push notifications per device |

---

## Account & Security

- Sign in with email/password or Google OAuth
- Session-based auth with CSRF protection
- First account created becomes the bootstrap admin
- Admin accounts can manage user roles from the Admin panel
- Admin panel controls global authentication settings (e.g. disabling password auth in favour of Google-only login)

---

## Admin Panel (admin users only)

| Section | Purpose |
|---|---|
| Dashboard | System-wide metrics: users, captures, OCR backlog, sync issues |
| Users | View all users, change roles between admin and standard |
| Captures | Browse all captures across all users with status detail |
| Operations | Sidekiq/background job health and queue monitoring |
| Settings | Global authentication settings (enable/disable password sign-in) |
