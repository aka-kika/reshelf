# Personal Note ("Why I saved this") — Design

**Date:** 2026-07-18
**Status:** Approved

## Problem

Kika clones repos for a reason and later forgets why. The existing `notes` field
can't serve this: Capture Assist auto-fills it with AI-generated descriptive text,
so a personal "why" would get mixed in or overwritten.

## Solution

A new, human-only text field on every project: `personalNote`. AI and automation
never write to it. It surfaces subtly in the Inspector as a collapsed disclosure
row — present when you look for it, invisible when you don't.

## Data model — `ToolProject.swift`

- New stored property `personalNote: String = ""` (default value → SwiftData
  lightweight migration; existing store untouched).
- New init parameter `personalNote: String = ""` (defaulted, so no call-site churn).
- Added to `matchesSearch(_:)` so search finds projects by your own words.
- No automation (Capture Assist, bulk fills, seed data) ever writes this field.

## Inspector — `InspectView.swift` + `AppSettings.swift`

- New `InspectorSection.personalNote` case. The existing decode logic appends
  unknown/missing cases, so saved custom section orders stay valid.
- Rendered as a collapsed disclosure row: small, dimmed `▸ Why I saved this`.
- Shows **even when empty** (unlike other sections) — otherwise there is no way
  to add the note from the Inspector. When empty the row reads as a faint
  affordance.
- Expanding reveals an inline `TextEditor`; edits save directly to the model
  (SwiftData autosave) — no sheet.
- New `showInspectorPersonalNote: Bool = true` setting, wired into
  `isVisible(_:)` / `setVisible(_:)` and the Settings section list, matching
  every other section.

## Capture & edit points

- **QuickCaptureSheet**: plain optional "Why I'm saving this" text field.
  Capture Assist does not populate it.
- **EditProjectSheet**: same field, below Notes.
- **AddProjectSheet**: intentionally skipped (YAGNI; can add later).

## Not doing

No list column, no markdown rendering, no timestamps, no privacy flag.

## Testing

- Build + run; verify existing store opens (migration adds the field).
- Add a personal note via Inspector disclosure; relaunch; confirm persisted.
- Verify search matches personal-note text.
- Verify Quick Capture and Edit sheet round-trip the field.
- Verify Settings toggle hides the section.
