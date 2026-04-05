# Architecture Overview

Inkcreate is a Rails 8 modular monolith built around one core idea: a notebook page capture is not just a scan, it is a knowledge object. The server remains the long-term system of record, while the PWA keeps drafts, queued uploads, and user intent available offline through IndexedDB and a service worker.

## Product architecture summary

- Rails owns persistence, domain logic, server-rendered UI, JSON APIs, background orchestration, auth, authorization, backup orchestration, OCR orchestration, and AI orchestration.
- The browser PWA owns camera capture, install UX, local drafts, offline queueing, and best-effort sync replay.
- PostgreSQL stores durable relational data, search metadata, OCR results, AI results, backup records, and sync records.
- Cloud object storage stores original notebook page images.
- OCR is manual-only. A capture can exist and be searchable by title, tags, description, project, and date even with no OCR text.
- AI is optional and explicit. Generated summaries and extracted tasks are stored and editable.
- Google Drive backup is adapter-based and optional.

## Runtime shape

- Public Rails app: browser HTML + JSON endpoints
- Background execution: Active Job with Sidekiq locally, Cloud Tasks or equivalent later
- PWA shell: service worker + manifest + Stimulus-driven controllers
- Direct upload path: browser requests signed upload URL, uploads original image, then finalizes a capture record

# Folder Structure

```text
app/
  controllers/
    admin/
    api/v1/
    concerns/
    internal/
    settings/
    web/auth/
  jobs/
  models/
  queries/
  serializers/
  services/
    ai/
    async/
    backups/
    captures/
    drive/
    observability/
    ocr/
    search/
    sync/
    uploads/
  views/
    admin/
    captures/
    capture_studio/
    daily_logs/
    home/
    install/
    inbox/
    landing/
    library/
    projects/
    search/
    settings/
    shared/
    tasks/
    web/auth/
db/
  migrate/
  seeds.rb
docs/
  architecture.md
public/
  manifest.json
  offline.html
  service-worker.js
  scripts/
    app.js
    indexed-db.js
    controllers/
    vendor/
test/
  integration/
```

# Domain and Database Schema

## Domain model

- `User`: auth identity, preferences, Drive connection state, admin/user role
- `AppSetting`: OCR mode, AI toggle, backup toggle/provider, image/privacy/retention preferences
- `Project`: long-term organizational workspace
- `DailyLog`: date-based organizational workspace
- `PageTemplate` / `NotebookPageTemplate`: reusable notebook page template catalog
- `PhysicalPage`: optional tracked physical page inventory for reused pages
- `Capture`: durable center of the knowledge graph
- `CaptureRevision`: immutable snapshot trail when a capture is edited or a physical page is reused
- `OCRDocument` / `OcrResult`: extracted text, provider metadata, confidence, bounding-box-ready metadata
- `AiSummary`: editable summary, bullet points, extracted tasks, structured entities
- `Attachment`: image, video, audio, file, URL, or YouTube link attached to a capture
- `Tag` and `CaptureTag`: lightweight user-defined retrieval layer
- `Task`: user task or AI-extracted task tied to a capture, project, or day
- `ReferenceLink`: graph edge between related captures
- `BackupRecord`: provider-neutral backup audit trail
- `DriveSync`: concrete Google Drive execution record used by the current backup adapter
- `SyncJob`: server-side representation of queued or replayed client sync work

## Database schema summary

Existing tables retained and extended:

- `users`
- `captures`
- `ocr_jobs`
- `ocr_results`
- `drive_syncs`
- `tags`
- `capture_tags`
- `page_templates`
- `notebooks` (legacy container retained for compatibility with the earlier API)

New tables added:

- `projects`
- `daily_logs`
- `physical_pages`
- `capture_revisions`
- `ai_summaries`
- `attachments`
- `tasks`
- `reference_links`
- `backup_records`
- `app_settings`
- `sync_jobs`

## Capture schema direction

`captures` now carries:

- core content: `title`, `description`, `page_type`
- organization: `project_id`, `daily_log_id`, `physical_page_id`
- preference flags: `favorite`, `archived_at`
- explicit processing state: `ocr_status`, `ai_status`, `backup_status`, `sync_status`
- offline tracking: `client_draft_id`, `last_synced_at`
- existing OCR pipeline fields: upload metadata, bucket/object key, searchable text, page template classification

## Search schema strategy

- `captures.search_text` remains the denormalized body for search
- `captures.search_vector` remains PostgreSQL full-text indexed text
- filters operate on `project_id`, `page_type`, `captured_at/created_at`, and tags

# Offline Storage Strategy

## IndexedDB

Stores:

- `draftCaptures`: local metadata for new or partially completed capture drafts
- `pendingUploads`: image/blob + draft payload + CSRF token for replay
- `syncEvents`: placeholder store for future richer client mutation tracking

Client-local data includes:

- draft title, page type, project/day destination, physical page selection
- preview data URL / thumbnail
- raw image blob queued for upload
- client draft idempotency key
- best-effort sync metadata

## PostgreSQL

Durable server state includes:

- captures and revisions
- OCR results
- AI summaries
- tasks
- projects and daily logs
- backup and sync audit records

## Object storage

- original captured notebook page images
- future attachment files when file upload support is expanded

## Background jobs

- OCR job dispatch and retry
- Google Drive backup dispatch and retry
- future AI enrichment async dispatch if providers become slow or billable

## Conflict strategy

- client generates `client_draft_id`
- server stores it on `captures`
- replay uses idempotent creation semantics keyed by client draft id
- latest server record becomes source of truth after successful finalize

# Routes and Pages

## Browser pages

- `/` -> signed-in home dashboard or signed-out landing page
- `/app` -> alias to signed-in dashboard
- `/capture` -> capture studio
- `/inbox` -> uncategorized captures
- `/projects` -> project list + create
- `/projects/:id` -> project detail
- `/daily` -> daily overview
- `/daily/:date` -> daily log detail
- `/captures/:id` -> capture detail
- `/search` -> global search
- `/tasks` -> task index/create/update
- `/library` -> attachment library
- `/settings` -> settings home
- `/settings/backup` -> backup settings
- `/settings/privacy` -> privacy settings
- `/onboarding` -> onboarding flow
- `/install` -> install guidance

## JSON endpoints

- auth/session endpoints
- upload URL issuance
- capture CRUD + manual OCR + AI summary + backup trigger
- projects CRUD
- daily logs index/show/create
- tasks index/create/update
- attachments index/create/destroy
- app settings show/update
- sync jobs index/create
- search endpoint

## Turbo/Hotwire note

The current scaffold keeps server-rendered HTML and small focused JavaScript modules. It does not yet add Turbo Streams or a full importmap pipeline, but the route and controller structure is already compatible with progressively enhancing forms and detail panels with Turbo later.

# Core Components and Stimulus Controllers

## Server-rendered components

- shared workspace navigation
- shared workspace header
- reusable capture card
- shared empty state
- admin shell (existing)
- auth shell (existing)

## Stimulus controllers

- `camera_controller`: starts camera preview and captures still frames
- `queue_controller`: saves offline drafts, stores upload blobs, requests signed URLs, finalizes captures, registers background sync
- `offline_status_controller`: reflects online/offline state in the UI
- `install_prompt_controller`: defers and triggers the install prompt
- `search_filters_controller`: progressive filter autosubmit

## PWA primitives

- `public/manifest.json`
- `public/service-worker.js`
- `public/scripts/indexed-db.js`
- `public/offline.html`

# Service Layer and Jobs

## Capture services

- `Captures::CreateCapture`
- `Captures::UpdateMetadata`
- `Captures::RequestOcr`
- `Captures::PreviewUrl`

## OCR services

- `Ocr::Pipeline`
- `Ocr::ImagePreprocessor`
- `Ocr::ProviderFactory`
- `Ocr::TesseractProvider`
- `Ocr::TemplateClassifier`

## AI services

- `Ai::ProviderFactory`
- `Ai::NullProvider`
- `Ai::SummarizeCapture`

## Backup services

- `Backups::ScheduleCaptureBackup`
- existing `Drive::ExportCapture`

## Sync services

- `Sync::RecordJob`

## Search/services

- `CaptureSearchQuery`
- `Search::CaptureIndexer`

## Background jobs

- `OcrCaptureJob`
- `DriveExportJob`

Planned next jobs:

- `AiCaptureSummaryJob`
- `ProjectDigestJob`
- `DailyRecapJob`
- `SyncReplayJob`

# Implementation Plan

## Phase 1: foundation

- extend schema for projects, daily logs, physical pages, revisions, attachments, AI summaries, backup records, and sync jobs
- switch capture creation to manual OCR by default
- add workspace pages and shared shell
- add IndexedDB + service-worker-backed upload queue

## Phase 2: reliability

- add richer file attachments
- add resumable upload state and progress UI
- add Turbo/Hotwire progressive updates for detail panels
- add stronger signed preview and image processing hooks

## Phase 3: enrichment

- add real AI provider adapters
- add project digest and daily recap jobs
- add task suggestion review UX
- add better handwriting OCR provider options

## Phase 4: hardening

- move current inline CSS into a formal Tailwind/Propshaft asset pipeline
- add Pundit policies
- add comprehensive request/system tests
- add storage quotas, export flows, and audit surfaces

# Code Scaffolding

The scaffold in this repository now includes:

- domain models for projects, daily logs, physical pages, attachments, tasks, reference links, AI summaries, backup records, app settings, and sync jobs
- extended capture model with manual OCR / AI / backup / sync state
- browser controllers and views for all required core pages
- API controllers for the new core resources
- a service-worker-backed IndexedDB queue
- locally vendored Stimulus runtime with focused capture/install/offline controllers
- capture preview, manual OCR trigger, AI summary creation, and backup scheduling services

Key implementation tradeoff:

- the current app still uses inline CSS in the Rails layout rather than a full Tailwind asset pipeline, because the repository started as an API-first app without an asset build stack. The view structure, PWA shell, and route/controller boundaries are now in place so Tailwind migration can happen as an isolated infrastructure step instead of being entangled with domain work.
