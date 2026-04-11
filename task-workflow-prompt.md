# Prompt — Build an App-Level Task Workflow (Google Tasks-style)

> Copy the section below and paste it into Claude (or any capable LLM) to generate the feature. It's a self-contained brief so no extra context is needed.

---

## Important: Tasks vs. Todos

This app has **two distinct features** that must coexist — do not merge or replace one with the other.

| | **Todos** (existing) | **Tasks** (to build) |
|---|---|---|
| **Scope** | Page-level | App/user-level (global) |
| **Where they live** | Inside a specific daily page (`Notepad › Apr 11 › Page 3`) | A dedicated top-level area accessible from the bottom nav |
| **Lifespan** | Lives and dies with that page — quick things to capture in the moment | Persistent across the whole app; survives regardless of which page you're on |
| **Use case** | "Buy milk today" · "Call Mom" · ephemeral jot-downs while you're writing that day's page | "Ship v2 launch" · "Prepare quarterly review" · real work items tracked over days/weeks/months |
| **Features** | Simple checkbox, optional reminder (already built) | Priority, severity, reminders, due dates, tags, subtasks, linking, filters, sort, group-by |
| **Data home** | `page.todos[]` | `user.tasks[]` |

**The existing page-level Todos stay exactly as they are.** This prompt is about building a *new*, separate Tasks feature that lives alongside them.

---

## The Prompt

Build a full **app-level Task management feature** for my **Daily Note Capture** app — a Google Tasks-caliber system that is completely separate from the existing page-level Todos. Deliver it as a single-file, interactive HTML prototype that matches my existing design language (cream/beige light theme with warm orange-red accent, Inter font, 22px card radii, subtle dotted background). All state in-memory (no localStorage).

### Context you should assume
- The app is a daily notepad where each day is a **Page** inside a **Chapter** inside a **Notebook**.
- Each page already has: voice notes, photos, **and its own page-level Todos**. Do not touch those.
- I'm adding a **new** top-level feature called **Tasks** that lives at the **user/app level**, not attached to any page.
- Tasks are accessed via a new entry in the bottom navigation (between Notebook and Notepad, or as a new tab replacing one of the existing ones — you decide what fits).
- Tasks are long-lived work items. Todos are quick jots on a page. They're intentionally different.
- Tasks **can reference** pages, voice notes, photos, etc. via a link field — but they are never *owned* by a page.

### Required capabilities

**1. Dedicated Tasks screen**
- New top-level screen, not inside any notebook/chapter/page.
- Accessible from the bottom navigation (add a "Tasks" item with a checkbox/target icon).
- Screen header: "Tasks" title, total count, and a "+ New task" primary action.
- Below the header: filter tabs, sort/group menu, then the task list.

**2. Task creation**
- Primary quick-add input at the top of the list — pressing Enter saves with default priority/severity.
- A "⋯ More details" affordance opens an expanded form (title, description, priority, severity, due date, reminder, link, tags, subtasks) before saving.
- Inline editing: click any field on an existing task to edit in place.

**3. Priority (4 levels)**
- `Low`, `Medium`, `High`, `Urgent`.
- 3px colored stripe on the **left edge** of the task card.
- Colors: green / gold / orange / red.
- Click the 🚩 flag to cycle, or pick from a dropdown in the detail view.
- Default: Medium.

**4. Severity (independent axis from priority)**
- `Trivial`, `Minor`, `Major`, `Blocker`.
- Uppercase badge next to the title with a soft colored background.
- Useful when a task represents a bug or critical issue needing triage.

**5. Reminders**
- Date + time picker with presets: *Later today*, *Tomorrow morning*, *Next week*, *Pick a time…*
- Recurrence: `none` / `daily` / `weekly` / `monthly` / `custom`.
- Shows as a **gold pill** on the card when set: 🔔 Apr 11 · 10:26 AM
- Bell icon turns gold when active.
- Use browser Notification API when fired; include a "Test fire" button in the toolbar for demo.

**6. Linking — the killer feature**
This is how Tasks connect back to the rest of the app. Each task can optionally link to *any* of:
- A **Notebook** (collection)
- A **Chapter** (section within a notebook)
- A **Page** (specific daily/note page) — the very same pages that hold page-level Todos
- A **Voice note** inside a page
- A **Photo** inside a page
- A **page-level Todo** inside a page (so an app-level Task can reference a specific page-level todo it originated from)

Display as a small pill under the task title showing the full path:
`📓 Work › Meetings › Apr 11 — Page 3`

Clicking the pill simulates navigation (log to console + flash a visual cue).

Provide a **Link picker modal** with:
- Searchable tree (Notebooks → Chapters → Pages → resources)
- "Recently linked" section at top
- Stub hierarchy data: ~3 notebooks × 2 chapters × 3 pages each, with some voice/photo/todo resources inside a few pages

**7. "Promote from Todo" and "Create from Task"**
Tasks and Todos are separate, but the two systems should interoperate:
- From a page-level Todo, a "Promote to Task" action creates a new app-level Task pre-filled with the todo's title and a link back to the source todo. The original todo remains on the page.
- From a Task's detail view, an "Add to page as Todo" action copies the task's title into a selected page's todo list and links them.
- Show this as an optional flow in the expanded task view with a tiny icon button: "↗ Sync to page".

**8. Due date (separate from reminder)**
- Date-only picker.
- Shown as a pill: 📅 Apr 15
- Turns red when overdue, orange when due within 24h.

**9. Tags / labels**
- Freeform comma-separated tags.
- Shown as chips next to severity.
- Click a tag to filter to it.

**10. Subtasks**
- Nested checkboxes inside the expanded task view.
- Progress count shown on parent: "2/5"
- Parent auto-completes when all subtasks are done.

**11. Organization & filtering**
- Filter tabs (segmented control): `All` / `Active` / `Done` / `Overdue` / `Today`.
- Each tab shows a count badge.
- Sort menu: Priority, Due date, Created, Manual (drag-to-reorder).
- Group-by menu: None, Priority, Severity, Due date, Linked notebook.
- Animated progress bar showing `done / total`.

**12. Keyboard shortcuts**
- `Enter` in the quick-add input — add task.
- `Esc` — close any open modal or detail panel.
- `⌘K` / `Ctrl+K` — focus the quick-add input.
- `Space` on a focused task — toggle done.

### Data model

```ts
// NEW — app/user level
type Task = {
  id: string
  title: string
  description?: string          // markdown supported
  done: boolean
  createdAt: Date
  completedAt?: Date

  priority: 'low' | 'medium' | 'high' | 'urgent'
  severity: 'trivial' | 'minor' | 'major' | 'blocker'

  dueDate?: Date
  reminder?: {
    at: Date
    recurrence?: 'none' | 'daily' | 'weekly' | 'monthly' | 'custom'
  }

  // Optional reference to app content — Tasks are NOT owned by any page
  link?: {
    type: 'notebook' | 'chapter' | 'page' | 'voice' | 'photo' | 'todo'
    notebookId?: string
    chapterId?: string
    pageId?: string
    resourceId?: string          // voice note / photo / todo id
    label: string                // pre-rendered path e.g. "Work › Meetings › Apr 11"
  }

  tags: string[]
  subtasks: { id: string; title: string; done: boolean }[]
  attachments: { type: 'photo' | 'voice'; id: string; url: string }[]
}

// EXISTING — do not change this, just document it for clarity
type PageTodo = {
  id: string
  pageId: string                 // lives inside a page
  text: string
  done: boolean
  reminder?: Date
  promotedTaskId?: string        // set if this todo has been promoted to an app-level Task
}
```

### UI anatomy

**Bottom nav (updated)**
```
 🏠 Home   📓 Notebook   ✓ Tasks   📌 Notepad   ⚙️ Settings
                           ↑ NEW app-level entry
```

**Tasks screen layout**
```
┌───────────────────────────────────────────────┐
│  TASKS                        4 active        │
│  ─────────────────────────────────────         │
│  [ + New task …                       ] [+]   │
│  [ All ][ Active ][ Done ][ Overdue ]          │
│  ▓▓▓▓▓░░░░░░░░   2 / 7                         │
│                                                 │
│  ┌───────────────────────────────────────┐    │
│  │ ▎ ○  Prepare demo deck    [MAJOR]     │    │
│  │     🔔 Apr 11 · 10:26 AM              │    │
│  │     📓 Work › Meetings › Apr 11       │    │
│  └───────────────────────────────────────┘    │
│  ┌───────────────────────────────────────┐    │
│  │ ▎ ✓  Call vendor         [MINOR]      │    │
│  └───────────────────────────────────────┘    │
└───────────────────────────────────────────────┘
```

**Collapsed task card**
- 3px left priority stripe
- Checkbox · title · severity badge · tags
- Meta row: reminder pill, due date pill, link pill
- Hover-reveal on the right: 🔔 bell · 🚩 flag · ✏️ edit · 🗑 delete

**Expanded detail panel** (slide-in drawer on wide screens; modal below 400px)
- Title (editable inline)
- Description (markdown textarea)
- Property grid: Priority · Severity · Due date · Reminder · Link · Tags
- Subtasks section with its own quick-add
- Attachments thumbnails
- "Sync to page" section (create a page-level todo from this task, or jump to the linked one)
- Activity log (created / completed / edited timestamps)
- "Delete task" destructive button at the bottom

**Link picker modal**
- Search bar
- "Recently linked" row (chips)
- Collapsible tree: Notebook → Chapter → Page → voice/photo/todo resources
- Breadcrumb preview of current selection
- "Link" / "Cancel" actions

### Visual style (must match existing app)
- **Background:** `#faf6ef` with subtle dotted pattern (radial-gradient dots, 18px)
- **Cards:** `#fffaf1` surface, 1px `rgba(27,27,29,0.08)` border, 22px radius, `0 2px 0 rgba(27,27,29,.04)` shadow
- **Accent:** `#ff5f4e` warm orange-red (FAB, primary actions, focused input glow)
- **Text:** `#1b1b1d` primary, `#5b5b66` secondary, `#9a9aa8` muted
- **Priority colors:** `#2eaa60` low · `#e0a92a` med · `#ff8a3d` high · `#e4534a` urgent
- **Severity soft backgrounds:** gold-soft / pink-soft / red-soft from the palette
- **Font:** Inter 400/500/600/700
- **Motion:** cubic-bezier(.34, 1.56, .64, 1) for check/progress/chevron; 200–300ms duration

### Micro-interactions
- Check circle: spring scale-in on toggle.
- Progress bar: fills with overshoot curve.
- Priority change: stripe color fades over 250ms.
- Add task: new row slides in from the top.
- Delete task: row fades + slides out 200ms before removal.
- Modal: backdrop fade + modal scale-in from 96% to 100%.
- "Promote to Task" / "Sync to page": a quick connecting-line animation between the two items.

### Accessibility
- All icon buttons have `aria-label`s.
- Focus rings visible (2px offset accent ring).
- Checkbox is a real `<button role="checkbox" aria-checked>`.
- Modals trap focus and return it to the trigger on close.
- Color never the only signal — every priority/severity has a text label too.
- Text contrast ≥ 4.5:1 throughout.

### Deliverable
One self-contained `tasks-screen.html` file with HTML + CSS + vanilla JS, seeded with:
- 6 example Tasks covering a variety of priority × severity combinations, some linked, some not
- 3 notebooks × 2 chapters × 3 pages of stub hierarchy data for the link picker
- A "Test fire reminder" button in the toolbar for demoing the notification flow
- A demo "Promote this todo to a Task" button (stubbed with a sample page todo) to show the interop

### Out of scope (do not build)
- Real backend / API
- Redesigning or modifying the existing page-level Todos
- Multi-user or sharing
- Cross-device sync
- Email / SMS reminder delivery
- Authentication

### Acceptance criteria
- [ ] Tasks is a **new top-level screen**, reachable from the bottom nav, clearly separate from any page.
- [ ] The existing page-level Todos are untouched.
- [ ] I can add a task with just Enter, or with full details via the expanded form.
- [ ] I can set priority and severity independently, and both are visually distinct.
- [ ] I can set a reminder with a preset or custom time, and see the gold pill update.
- [ ] I can link a task to a Notebook / Chapter / Page / voice / photo / todo via the picker, and the pill shows the full path.
- [ ] I can "Promote" a sample page-level todo into a new app-level Task, and the link between them is preserved.
- [ ] Filter tabs correctly partition the list; counts update live.
- [ ] Progress bar animates when I check/uncheck.
- [ ] All keyboard shortcuts work.
- [ ] Visual style is indistinguishable from the existing `daily-note-light.html` theme.

---

## How to use this prompt

1. Paste everything between the `## The Prompt` heading and the final `---` into a fresh Claude conversation.
2. Attach your current `daily-note-light.html` so the model can match the existing styles exactly and see the page-level Todo UI it needs to coexist with.
3. Ask for iterations — e.g. *"now add drag-to-reorder"*, *"add a kanban board view"*, or *"build the promote-to-task animation"*.
