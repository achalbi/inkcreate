# Implementation Prompt: Voice Notes, Reminders, and To-Do Lists

## Goal

Extend the app with three new capabilities, in this priority order:

1. **Voice notes** — record, store, and play back audio clips attached to a page (dedicated `VoiceNote` model).
2. **Reminders** — a standalone reminder system. Reminders can be attached to a **to-do item** (Feature 3) OR exist on their own with no model association. All upcoming reminders are surfaced on the **Home page** in a dedicated "Upcoming reminders" section.
3. **To-do lists on pages** — opt-in checklist with check/uncheck. Each to-do item can optionally have a reminder.

Notification delivery is **Web Push**. A user has many **devices**; each device can independently have push enabled or disabled. When a reminder fires, the notification is pushed to **every enabled device** belonging to the user.

---

## Context — what already exists

- Models: `User → Notebook → Chapter → Page` (`app/models/page.rb`)
- Page already uses Active Storage (`has_many_attached :photos`) and rich notes (`RichNotes` concern).
- Validation today requires either notes or at least one photo (`notes_or_photos_present`).
- Google Drive export hooks exist on the page lifecycle (`Drive::RenameRecordFolder`).
- Time zones are user-locked (`add_time_zone_locked_to_users` migration).
- UI is server-rendered ERB with a workspace layout in `app/views/notebooks/`.
- Home dashboard exists at `dashboard_path` (referenced from the notebooks index breadcrumbs).

When implementing, **read these files first** to align with existing patterns:
- `app/models/page.rb`
- `app/models/notebook.rb`, `app/models/chapter.rb`
- `app/views/notebooks/show.html.erb` (page rendering)
- `app/controllers/notebooks_controller.rb`
- The dashboard view/controller (find via `dashboard_path` in `routes.rb`)
- The most recent migration in `db/migrate/` for naming/style conventions

---

## Feature 1 — Voice Notes (dedicated model)

### User stories
- As a user, on a page I can tap a "Record voice note" button, record audio through my browser/device microphone, and save it to the page.
- I can see all voice notes attached to a page in chronological order with duration, recorded-at timestamp, and a play/pause control.
- I can delete a voice note I no longer want.
- The page validation should accept a voice note as valid content (alongside notes/photos).

### Functional requirements
- Recording works in Chrome/Safari/Firefox on desktop and on iOS/Android Safari/Chrome.
- Show a live recording indicator (timer + pulsing dot) while recording.
- Maximum recording length is 120 minutes; auto-stop when reached.
- Show file size and duration after recording. User confirms before saving.
- Playback: standard play/pause/scrub controls. Use the native `<audio>` element with custom styling.
- Deleting a voice note removes the underlying blob.

### Data model — **dedicated `VoiceNote` model (decided)**

```
voice_notes
  belongs_to :page
  has_one_attached :audio
  duration_seconds: integer
  recorded_at: datetime
  byte_size: integer
  mime_type: string
  transcript: text (nullable, reserved for future)
  timestamps
```

- Add `has_many :voice_notes, dependent: :destroy` to `Page`.
- Index: `voice_notes(page_id, recorded_at)`.

### Page content validation rewrite
Replace the existing `notes_or_photos_present` validation with a new `content_present?` check. A page is valid if **any one** of the following is present:
- `notes` (rich text), OR
- at least one attached `photo`, OR
- at least one `voice_note`, OR
- at least one `todo_item` on the page's `todo_list` (only counted when the list is enabled)

```ruby
def content_present?
  return if notes.present?
  return if photos.attached? || pending_photo_blobs.any?
  return if voice_notes.any?
  return if todo_list&.enabled? && todo_list.todo_items.any?

  errors.add(:base, "Add notes, a photo, a voice note, or a to-do item.")
end
```

### Technical approach
- Use the **MediaRecorder Web API** in the browser. Record as `audio/webm;codecs=opus` (Chrome/Firefox) or `audio/mp4` (Safari).
- Upload via Active Storage direct upload (`rails_direct_uploads_url`).
- Stimulus controller: `app/javascript/controllers/voice_recorder_controller.js`.
- Server: `app/controllers/pages/voice_notes_controller.rb` with `create` and `destroy`.
- Compute `duration_seconds` client-side from the MediaRecorder timer and pass it as a param; verify server-side using `ffprobe` if available, otherwise trust the client.

### Out of scope for v1
- Server-side transcription (schema field is reserved but unused).
- Voice-note editing (trim/cut).
- Sharing voice notes externally.

---

## Feature 2 — Reminders (standalone + Web Push)

### Decisions captured
- **Reminders are NOT attached to pages.** They are their own first-class entity.
- A reminder may attach to a **to-do item** (Feature 3) **OR** be standalone with no association.
- The **Home page** has an "Upcoming reminders" section listing all of the user's pending reminders across both kinds.
- **Web Push is the notification channel.** A user has many **devices**. Each device can independently have push enabled/disabled. When a reminder fires, the push is delivered to **every enabled device** the user owns.

### User stories
- As a user, I can create a standalone reminder from the Home page (title, date, time, optional note) without it being tied to anything.
- I can also create a reminder from a to-do item (Feature 3) — see that section.
- All my pending reminders show on the Home page sorted by next-fire time, with a relative time label ("in 12 min", "tomorrow at 9 am").
- When a reminder fires, I receive a Web Push notification on every one of my devices that has push enabled.
- Tapping the push notification opens the app to the reminder's source (the to-do item's page, or the standalone reminder edit screen).
- I can edit, snooze (10 min, 1 hr, tomorrow same time, custom), or dismiss a reminder.
- Past reminders show as "Triggered" with a timestamp; not deleted.

### Data model

```
reminders
  belongs_to :user
  belongs_to :target, polymorphic: true, optional: true   # nullable → standalone
  title: string
  note: text (nullable)
  fire_at: datetime (indexed, UTC)
  status: enum [pending, triggered, snoozed, dismissed]
  last_triggered_at: datetime
  snooze_until: datetime (nullable)
  timestamps

  index: (user_id, fire_at, status)
  index: (target_type, target_id)
```

- `target` is polymorphic so a `TodoItem` reminder and a standalone reminder use the same table and the same scheduler.
- Standalone reminder = `target_type` and `target_id` both `NULL`.

### User devices (Web Push enabled per device)

A user **has many devices**. Each device represents one browser/installation where the user has registered with the app. Push notifications can be enabled or disabled independently on each device. When a reminder fires, the dispatcher iterates over the user's devices and pushes to every device that has push enabled.

```
devices
  belongs_to :user
  label: string (nullable)            # user-editable friendly name ("MacBook", "iPhone")
  user_agent: string                  # captured at registration, used to suggest a label
  push_enabled: boolean default false
  push_endpoint: text (nullable)
  push_p256dh_key: string (nullable)
  push_auth_key: string (nullable)
  last_seen_at: datetime
  timestamps

  index: (user_id, push_enabled)
  unique index: (push_endpoint) where push_endpoint is not null
```

- One row per browser/device the user uses with the app.
- Push fields are populated when the user taps "Enable notifications" on that device. They are nullable so a device can exist without push being enabled.
- The dispatcher uses **only** `push_enabled = true` as the filter; if `push_enabled` is false, the row stays around (so the user's device list in settings is preserved) but no push is sent.
- Use the `web-push` gem (`gem "web-push"`).
- Generate a VAPID keypair once during app setup, store in Rails credentials (`config/credentials.yml.enc`):
  ```
  vapid:
    public_key: ...
    private_key: ...
    subject: mailto:support@<domain>
  ```
- Service worker (`public/sw.js` or `app/javascript/service_worker.js`) handles `push` events and shows the system notification.
- Settings screen lists all of the user's devices with their label, last-seen time, push status, and "Enable / Disable on this device" + "Remove device" actions.
- Enable-on-this-device flow:
  1. User taps "Enable notifications on this device".
  2. JS asks for `Notification.requestPermission()`.
  3. If granted, JS calls `pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: <vapid public key> })`.
  4. POST the resulting endpoint + keys to `/devices/:id/enable_push` (creates the device row on first registration if needed).
  5. Server sets `push_enabled = true` and stores the endpoint/keys.
- Disable-on-this-device flow: clears `push_enabled` and the stored push fields. The device row remains so it can be re-enabled later.

### Job scheduling
- Use **Solid Queue** recurring jobs (Rails 8 default — no extra infra).
- Recurring job runs every minute: `DispatchDueRemindersJob`.
- Query: `Reminder.where(status: :pending).where("fire_at <= ?", Time.current)`.
- For each due reminder:
  - Mark `status = :triggered`, set `last_triggered_at`.
  - Load the user's devices where `push_enabled = true`.
  - Enqueue `DeliverReminderPushJob.perform_later(reminder, device)` for each such device.
  - On 410/404 from the Web Push response → flip that device's `push_enabled = false` and clear its push fields. The device row is preserved.
- Snooze flow: setting `snooze_until` flips status to `:snoozed`; a separate sweeper (or the same job) re-arms it to `:pending` with `fire_at = snooze_until` once `snooze_until <= now`.

### Home page "Upcoming reminders" section
- New partial: `app/views/dashboard/_upcoming_reminders.html.erb`.
- Renders the next N (e.g. 8) `pending` reminders for `current_user`, sorted by `fire_at`.
- Each row shows: title, relative time, source (e.g. "from to-do: Buy milk" or "Standalone"), edit/dismiss buttons.
- Empty state: "No upcoming reminders — create one to get a push notification when it's time."
- A "+ New reminder" button opens a modal/form to create a standalone reminder.

### Time zones
- Always store `fire_at` in UTC.
- Always render and accept input in `current_user.time_zone`.
- Use `Time.use_zone(current_user.time_zone) { ... }` in controllers/views.

---

## Feature 3 — To-Do Lists on Pages

### User stories
- As a user, on a page I can toggle "Enable to-do list". When enabled, the page shows a checklist section.
- I can add items, edit text inline, reorder via drag handle, check/uncheck, and delete items.
- **Each to-do item can have a reminder** (using the Feature 2 reminder system). Setting a reminder on an item creates a `Reminder` row with `target = todo_item`.
- When the reminder fires, I get a Web Push the same way standalone reminders do.
- Checked items are visually de-emphasized (strikethrough, faded) but stay in place; option to "Hide completed" to collapse them.
- Progress indicator on the page card (e.g. `3 / 7 done`) when a list is active.

### Data model

```
todo_lists
  belongs_to :page
  enabled: boolean default true
  hide_completed: boolean default false
  timestamps

todo_items
  belongs_to :todo_list
  content: string
  completed: boolean default false
  completed_at: datetime
  position: integer
  timestamps

  index: (todo_list_id, position)
```

- A to-do item's reminder lives in the `reminders` table with `target_type = "TodoItem"` and `target_id = todo_items.id`. There is **no** `due_at` column on `todo_items`.
- `has_one :reminder, as: :target, dependent: :destroy` on `TodoItem` (one reminder per item for v1; the schema allows many).

### Functional requirements
- Checking/unchecking is instant (Turbo / Stimulus) — no page reload.
- Adding an item is one tap and immediately editable.
- Reordering persists across reloads.
- Disabling the to-do list does **not** delete items — they're hidden but recoverable.
- An enabled to-do list with at least one item satisfies the page's `content_present?` validation.

### Endpoints
- `app/controllers/pages/todo_lists_controller.rb` → enable/disable, toggle hide_completed.
- `app/controllers/pages/todo_items_controller.rb` → `create`, `update`, `destroy`, `reorder`, `toggle`.
- Reminders for items go through the standard reminders controller with the polymorphic target.

### Out of scope for v1
- Sub-tasks / nesting.
- Multiple reminders per item.
- Recurring item reminders.

---

## Cross-cutting concerns

### Notification infrastructure (built once in Phase 2, reused by Feature 3)
- `web-push` gem with VAPID keys in Rails credentials.
- `Device` model — a user has many devices, each with optional push credentials and a `push_enabled` flag.
- `WebPushDeliverer` service object — takes `(device, payload_hash)`, handles errors, flips `push_enabled = false` on dead devices.
- Service worker registered on first authenticated page load.
- Settings screen for managing devices and per-device push state.

### Background jobs
- **Solid Queue** with recurring jobs.
- `DispatchDueRemindersJob` — runs every minute.
- `DeliverReminderPushJob` — one job per (reminder × device).

### Time zones
All reminder timestamps round-trip through `user.time_zone`. UTC in DB, user TZ on input/render.

### Mobile UX
The app is mobile-first (375px viewport):
- Voice recorder mic is a clear FAB-style control with a 56px hit target.
- To-do checkboxes need a 44px hit target.
- Reminder time pickers use the native `<input type="datetime-local">` on mobile.
- Push permission prompt only appears after a user gesture (tap on "Enable notifications") — never on page load.

### Tests
For each feature, add:
- Model specs / validations
- Request specs for new controllers
- A system spec for the happy path:
  - Voice notes: record → save → playback
  - Reminders: create standalone reminder → fast-forward time → assert `DispatchDueRemindersJob` enqueues a push delivery → assert each enabled device receives the payload (stub `web-push`)
  - To-dos: create list → add 3 items → check 1 → assert "1 / 3 done" → set reminder on item → assert reminder row created with correct polymorphic target

---

## Deliverables expected from the implementation plan

When you (the implementing agent) write the actual implementation plan, please produce:

1. **Migration list** with column types and indexes (voice_notes, devices, reminders, todo_lists, todo_items).
2. **Model diff** for `Page` (associations, validations, the `content_present?` rewrite that accepts notes OR photo OR voice note OR to-do item).
3. **New model files** — `VoiceNote`, `Device`, `Reminder`, `TodoList`, `TodoItem`.
4. **Route additions** (RESTful, with the standalone reminders routes on the dashboard, plus `devices#enable_push` / `devices#disable_push` member routes).
5. **Controller stubs** (action names + redirect/render targets).
6. **View/partial structure**:
   - Page show partials for voice notes section + to-do list section
   - Dashboard partial for "Upcoming reminders"
   - Settings partial for device management (list of devices with per-device push toggle)
7. **JavaScript** — Stimulus controllers (`voice_recorder`, `todo_list`, `reminder_form`, `device_push`) plus the service worker.
8. **Job classes** with schedule/trigger conditions.
9. **VAPID setup steps** — how to generate the keypair and where to store it.
10. **Phased rollout**:
    - **Phase 1 — Voice notes.** No scheduler, no notifications. Smallest. Ships independently.
    - **Phase 2 — Push infrastructure + standalone reminders + Home upcoming-reminders section.** Builds the entire notification pipeline end-to-end with the simplest possible target (no association).
    - **Phase 3 — To-do lists, with item reminders reusing the Phase 2 plumbing.**
11. **Open questions** that need a product decision before coding starts.

---

## Out of scope (explicit non-goals for v1)

- AI transcription of voice notes.
- Recurring reminders (daily/weekly).
- Sub-tasks / nested to-do items.
- Sharing voice notes / to-do lists with other users.
- Email or SMS notification channels — Web Push only.
- service worker to be used for notifications
---

## Success criteria

- A user can record a 30-second voice note on a page and play it back across desktop and mobile.
- A user can enable Web Push on their laptop and their phone independently, see both listed in settings, and receive the same reminder notification on both devices.
- A user can create a standalone reminder for 5 minutes from now from the Home page and receive a Web Push when it fires.
- A user can enable a to-do list on a page, add 3 items, check 1, see "1 / 3 done" on the page card, attach a reminder to an unchecked item, and receive a push when it fires that opens the parent page.
- All existing page tests still pass.
- No regressions in the existing notebook/chapter/page CRUD flows.
