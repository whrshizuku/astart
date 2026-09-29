> This is the in-app version of the manual. If the in-app manual and the files in the repository (https://github.com/whrshizuku/astart) ever diverge, the repository files always take precedence.

Start (启序) is a local note-taking tool that breaks to-dos into small steps, helping you focus on one thing at a time. Designed for neurodivergent users: encouraging wording, low friction, zero blame. All data lives on-device by default; beyond update checks, online speech, AI assistant and cloud backup are all opt-in and only connect when you actively use them.

> Originality & AI disclosure: this app is designed independently by the author. AI tools assisted only the coding phase — product design, interaction logic and workflow are fully the author's original work. AI does not participate in any design decisions.

> Extended features are in preview: only API stubs remain, the core interaction is temporarily removed. Please wait for future updates.

# Home

Top to bottom: Focus, big clock, Schedule, Anytime. Plain text list, scan it in one glance. A gentle reminder sits next to the clock — when the day is done it reads "Today's all done — nice work".

Both sections (Schedule and Anytime) share the **same interaction model**:
- **Long-press head (left), 120ms = drag**: drop into the **red trash zone at the bottom** (5-second undo), or cross-module shortcuts (drop an Anytime item into the Schedule area = pick a time to convert it; drop any row to the top = make it the Focus).
- **Long-press tail (right) = enter multi-select**. In multi-select the head becomes a gray drag handle; the tail has the one-and-only check circle (colored = selected). The top bar keeps just **Select all** (gray outline, secondary) and **Done** (red solid, primary). Deletion always goes through the bottom trash.
- **Drag between rows to reorder**: a highlighted gap appears on long-press (including a top gap to pin on top). Drag up to pin, down to move. Order persists after restart.

# Focus

The big headline at the top. With no Focus it shows "One thing at a time". Tap "Let's start": pick from today's unfinished items, or write a new one — or long-press the head of any row and drag it to the top to make it Focus. Enter the Focus timer from the Focus tab in the bottom bar.

Once chosen, the title shows up big. The main button "Do this one" jumps straight to the steps page to break it down; you can also finish it, pick another, or edit. Completing it shows "Main goal done — beautiful"; tap "Next" to keep going.

# Schedule

Timed tasks are sorted by **manual rank first** (written by drag-to-reorder), falling back to `dueTime`; time shown on the right. Overdue items just show the date — no red, no scolding. Today's phone-calendar events appear alongside as small dots, deduplicated automatically. Future schedules simply show up when their day arrives. Completed schedules leave the list; their records stay in stats and search.

- **Drag-to-reorder inside Schedule**: same unified interaction as the home sections.
- **Small circle at row end**: "Skip it" (undoable) or "Do it another day" (tomorrow / the day after / in three days / pick a date).
- **Long-press "Schedule" heading** to enter multi-select; top bar has Select all + Done; drop into the bottom red trash to delete.
- **Create new** (plus at top right): write several on separate lines, pick one shared date and time.
- **On-time floating reminders** are on by default. "Add to calendar" and "System alarm" are optional — tap the matching button in the editor, or light up the chip when batch-creating, to trigger them.

# Anytime

Everything without a time lives here. The top-right plus lets you write several at once — lines and sentence punctuation split them automatically.

- **Drag-to-reorder inside Anytime**: same unified interaction as the home sections.
- **Drag an item into the Schedule area**: opens the editor for date/time. Only saves after you confirm — canceling leaves the original untouched.
- **Tap row end** to open the editor and assign a time.

# Mind Map

- **Top bar**: Bulk import (pick Schedule / Anytime / Steps to copy under the map root) + Re-layout.
- **Bottom toolbar**: When root is selected = Add child (accent main) + Bulk; when non-root selected = Add child + Edit + Bulk; when nothing selected = Bulk only. **Deletion always goes through the bottom red trash** (long-press node 120ms to start dragging); there is no delete button in the toolbar.
- **Node interactions (fully decoupled, zero conflict)**:
  - **Tap** = select; **double-tap** = edit text.
  - **Press & drag (Listener raw pointer)** = free placement of the whole subtree; **pinch to zoom**; Re-layout button restores auto layout.
  - **Long-press 120ms → drag into bottom red trash**: delete this node (cascade), 5-second undo. **Root is locked** (cannot be dragged, cannot be deleted). Matches home / search / steps exactly.
- **Import nodes**: copy Schedule / Anytime / Steps into the map (top bar imports under root; toolbar button imports under the selected node). Original items stay in place.

# Haptic & Visual Feedback

- **On drag start**: `mediumImpact` vibration + 120ms long-press trigger + floating feedback at `scale 1.02` + soft shadow + rounded corners.
- **On hover** (over sort gap / trash / schedule drop zone): edge-triggered vibration (once per entry, not continuous) + highlighted gap with shadow.
- **On long-press-to-select / tap-check**: `selectionClick` vibration.

# Medication

The capsule icon, first slot of the bottom bar. Flip through dates to see each day's medicine, sorted by time; each card shows the name, dose, time and category. The plus button at bottom right creates a plan: enter the name, add dose times one by one (24-hour clock), and optionally dose, category, start/end dates; on save, on-time reminders are set daily and bound to system alarms (rolling 30 days ahead). The calendar icon at top right switches to a month view — the dot under each date tells the story at a glance: green = all doses taken, yellow = partially taken, tomato red = missed (grey = future). Tap the circle on a card to log that dose as taken. Medication data is stored separately and never appears in home lists or search results.

# Search

The magnifier in the top bar, left of Settings. Searches all items (Schedule, Anytime, Steps) by title or note. Tap a result to edit. Interaction matches the home sections: **long-press head → red trash delete** (5s undo); **long-press tail → multi-select**; top bar Select all + Done.

# Quick capture

The red center button in the bottom bar. Tap for a quick text note: write first, sort never; tap "Dump in" and it splits by lines and sentence punctuation (。！？；…) into items, then takes you to sorting.

# Sort it out

The input bar at the bottom takes quick notes directly: write several on separate lines and they're split into inbox items on save. Sort each item as a Schedule (pick date and time) or Anytime; it then flows into the matching area on the home page.
In the mind map, tap a node to select it, then add a child or sibling, edit, or delete; drag to move it with its whole subtree, and pinch to zoom.
The top-right plus creates a single inbox item; "Bulk organize" opens bulk actions with select-all.

# Reminders & calendar

Once a schedule has a time, on-time floating reminders are on by default; "Add to calendar" and "System alarm" are optional — they only run when you tap the matching button in the editor (or light up the chip when batch-creating). Medication plans automatically get daily reminders bound to system alarms on save, and deleting a plan cancels them.
All reminders run on the device and re-arm automatically after a reboot or after the app is swiped away; the switches live in Settings.

# Focus & stats

Focus: only the ring and countdown number, no distractions. Duration chosen before entering: presets 2 / 25 / 45 min, or custom 1–240 min. Current duration shown big. Minute tick, completion tone / vibration / silent, and volume are adjustable in Settings.
Stats: by date, swipe left/right. Four big numbers per page: focus minutes, focus sessions, items completed, items added. Below is a 24-hour focus bar chart. Pure numbers, objective.

# Data & update

Search can find and delete any item — undoable. Settings has JSON export/import with automatic snapshot before import. Uninstalling wipes everything — export first. Updates arrive automatically.

# Extended features (preview, API only)

Settings → Extended has three opt-in capabilities: online speech recognition (allows system online engines for better accuracy), AI assistant (free default or your own OpenAI-compatible endpoint; only sends when you tap "AI sort"), cloud backup (WebDAV to your own server or Jianguoyun; manual trigger only). Leave them off and the app never phones home.

# About the design

The author is a Smartisan OS user. Smartisan's Big Bang, One Step and Quick Capsule all inspired this app — the good ideas were gently picked out and reimplemented, with sincere thanks to the Smartisan OS team. Design goals: plain text lists, consistent tomato-red strokes, low-friction wording. Hopefully Start can quietly help you get things done.

~ Start

~ ── 工匠的骄傲与喜悦 · PRIDE & JOY ──
