# Personal Note ("Why I saved this") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a human-only `personalNote` field to every catalog project — captured at clone time, surfaced as a subtle collapsed disclosure in the Inspector — so Kika never forgets why she cloned something.

**Architecture:** One new SwiftData string property on `ToolProject` (default `""` → lightweight migration, existing store untouched). A new `InspectorSection` case renders it via a small self-contained `PersonalNoteSection` subview with inline editing (SwiftData autosave — no explicit save call needed). Plain text fields in Quick Capture and the Edit sheet round-trip it. No AI/automation path ever writes it.

**Tech Stack:** Swift / SwiftUI / SwiftData, macOS app, Xcode project `OpenSourceShelf.xcodeproj`, scheme `OpenSource Shelf`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-18-personal-note-design.md`.
- **No AI writes:** Capture Assist / suggestion code must never touch `personalNote`. Do not add it to any suggestion-apply function.
- **Pre-existing uncommitted work:** `OpenSourceShelf/Views/ContentView.swift` (whole file) and one line of `OpenSourceShelf/Views/InspectView.swift` (line ~124, `presentSheetAfterEndingTextEditing`) carry an unrelated sheet-freeze fix. NEVER `git add` ContentView.swift. For InspectView.swift, this plan assumes that pending line was committed separately before Task 3 (see handoff note); if it wasn't, stop and ask.
- Build command (expect `** BUILD SUCCEEDED **`; ignore SourceKit warnings):
  `xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -configuration Debug build 2>&1 | tail -5`
- There is no unit-test target in this project. Each task's gate is a clean build; final task is a scripted+manual verification pass.
- Commit only the files each task names, using `git commit --only <paths>`.

---

### Task 1: Model field

**Files:**
- Modify: `OpenSourceShelf/Models/ToolProject.swift`

**Interfaces:**
- Produces: `ToolProject.personalNote: String` (stored, default `""`); init parameter `personalNote: String = ""` positioned after `notes`; `matchesSearch(_:)` matches it.

- [ ] **Step 1: Add the stored property**

In `ToolProject.swift`, after line 18 (`var notes: String = ""`), add:

```swift
    /// Kika's own "why I saved this" — never written by AI or automation.
    var personalNote: String = ""
```

- [ ] **Step 2: Add the init parameter and assignment**

In the `init`, after `useCases: [String] = [],` / `notes: String = "",` add a parameter:

```swift
         notes: String = "",
         personalNote: String = "",
```

and after `self.notes = notes` add:

```swift
        self.personalNote = personalNote
```

- [ ] **Step 3: Include in search**

In `matchesSearch(_:)`, after the `|| notes.lowercased().contains(q)` line, add:

```swift
            || personalNote.lowercased().contains(q)
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add OpenSourceShelf/Models/ToolProject.swift
git commit --only OpenSourceShelf/Models/ToolProject.swift -m "Add personalNote field to ToolProject

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Inspector section enum + settings flag

**Files:**
- Modify: `OpenSourceShelf/Models/AppSettings.swift`

**Interfaces:**
- Consumes: nothing from Task 1 (independent).
- Produces: `InspectorSection.personalNote` (raw value `"personalNote"`, displayName `"Why I Saved This"`, icon `"quote.bubble"`, `isIntelligence == false`); `AppSettings.showInspectorPersonalNote: Bool = true` wired into `isVisible(_:)` / `setVisible(_:)`.

Note: `inspectorSectionOrder`'s decoder already appends missing cases, and `SettingsView` builds its rows from the ordered cases — the new section appears in Settings with no SettingsView change.

- [ ] **Step 1: Add the enum case**

In `InspectorSection`, after `case notes = "notes"`, add:

```swift
    case personalNote = "personalNote"
```

In `displayName`, after `case .notes: "Notes"`, add:

```swift
        case .personalNote: "Why I Saved This"
```

In `icon`, after `case .notes: "note.text"`, add:

```swift
        case .personalNote: "quote.bubble"
```

(`isIntelligence` needs no change — `default: false` covers it.)

- [ ] **Step 2: Add the visibility flag and wire it**

In `AppSettings`, after `var showInspectorNotes: Bool = true`, add:

```swift
    var showInspectorPersonalNote: Bool = true
```

In `isVisible(_:)`, after `case .notes: return showInspectorNotes`, add:

```swift
        case .personalNote: return showInspectorPersonalNote
```

In `setVisible(_:)`, after `case .notes: showInspectorNotes = value`, add:

```swift
        case .personalNote: showInspectorPersonalNote = value
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **` (the `inspectorSectionContent` switch in InspectView.swift is NOT exhaustive-over-enum — it switches on the section passed in; verify no "switch must be exhaustive" error. If one appears in `InspectView.swift`, add a temporary `case .personalNote: EmptyView()` there; Task 3 replaces it.)

- [ ] **Step 4: Commit**

```bash
git add OpenSourceShelf/Models/AppSettings.swift
git commit --only OpenSourceShelf/Models/AppSettings.swift -m "Add Why I Saved This inspector section case and visibility flag

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(If Step 3 required the temporary `EmptyView()` case in InspectView.swift, do NOT commit InspectView.swift here — leave it for Task 3.)

---

### Task 3: Inspector disclosure UI

**Files:**
- Modify: `OpenSourceShelf/Views/InspectView.swift`

**Interfaces:**
- Consumes: `ToolProject.personalNote` (Task 1), `InspectorSection.personalNote` + `showInspectorPersonalNote` (Task 2).
- Produces: `PersonalNoteSection` (private view in InspectView.swift, `init(project: ToolProject)`).

- [ ] **Step 1: Render the section in the switch**

In `inspectorSectionContent(_:)` (around line 176), after the `case .notes:` block, add (replacing any temporary `EmptyView()` case from Task 2):

```swift
        case .personalNote:
            // Unlike other sections this renders even when empty — the collapsed
            // row is the only affordance for adding the note from the inspector.
            if inspectorSettings.showInspectorPersonalNote {
                Divider().padding(.vertical, 16)
                PersonalNoteSection(project: project)
            }
```

- [ ] **Step 2: Add the subview**

At the bottom of `InspectView.swift` (file scope, after the `InspectView` struct's closing brace), add:

```swift
/// Collapsed "Why I saved this" note with inline editing. Edits write straight
/// to the model; SwiftData autosave persists them without an explicit save.
private struct PersonalNoteSection: View {
    @Bindable var project: ToolProject
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Why I saved this")
                        .font(.system(size: 11, weight: .medium))
                    if !isExpanded, !project.personalNote.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary.opacity(0.7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                TextEditor(text: $project.personalNote)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 54)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(alignment: .topLeading) {
                        if project.personalNote.isEmpty {
                            Text("The reason you cloned this — future you will thank you.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 12)
                                .padding(.leading, 11)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

Precondition: `git diff OpenSourceShelf/Views/InspectView.swift` must show ONLY this task's changes (the pre-existing sheet-freeze line was committed before this plan started). If it shows the unrelated `presentSheetAfterEndingTextEditing` hunk as uncommitted, STOP and ask the user.

```bash
git add OpenSourceShelf/Views/InspectView.swift
git commit --only OpenSourceShelf/Views/InspectView.swift -m "Show collapsed Why I Saved This section in the inspector

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Quick Capture field

**Files:**
- Modify: `OpenSourceShelf/Views/QuickCaptureSheet.swift`

**Interfaces:**
- Consumes: `ToolProject` init parameter `personalNote:` (Task 1).
- Produces: nothing consumed later.

- [ ] **Step 1: Add state**

Next to the other editable fields (after `@State private var notes: String = ""`, around line 40), add:

```swift
    /// Human-only; Capture Assist never fills this.
    @State private var personalNote: String = ""
```

- [ ] **Step 2: Add the field to the main capture view**

In `body`, directly after the `HStack(alignment: .top, spacing: 16) { field("Shelf") { ... } field("Category") { ... } }` block (before `moreDetailsDisclosure`, around line 134), add:

```swift
                        field("Why") {
                            TextField("Why you're saving this (optional)", text: $personalNote)
                        }
```

- [ ] **Step 3: Grow the sheet to fit the new row**

In `sheetHeight` (around line 152), change:

```swift
        if fetchedInfo == nil { return 240 }
        return showsMoreDetails ? 700 : 560
```

to:

```swift
        if fetchedInfo == nil { return 240 }
        return showsMoreDetails ? 740 : 600
```

- [ ] **Step 4: Pass it through on save**

In `saveProject()`, in the `ToolProject(` initializer call, after `notes: notes.trimmingCharacters(in: .whitespaces),` add:

```swift
            personalNote: personalNote.trimmingCharacters(in: .whitespaces),
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add OpenSourceShelf/Views/QuickCaptureSheet.swift
git commit --only OpenSourceShelf/Views/QuickCaptureSheet.swift -m "Capture the why at clone time in Quick Capture

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Edit sheet field

**Files:**
- Modify: `OpenSourceShelf/Views/EditProjectSheet.swift`

**Interfaces:**
- Consumes: `ToolProject.personalNote` (Task 1).
- Produces: nothing consumed later.

- [ ] **Step 1: Add state initialized from the project**

After `@State private var notes: String` (around line 18), add:

```swift
    @State private var personalNote: String
```

In the `init`, after `self._notes = State(initialValue: project.notes)` (around line 37), add:

```swift
        self._personalNote = State(initialValue: project.personalNote)
```

- [ ] **Step 2: Add the form field**

Directly after the `field("Notes") { ... }` block (which ends around line 143), add:

```swift
                    field("Why I Saved This") {
                        TextEditor(text: $personalNote)
                            .frame(height: 50)
                            .overlay(alignment: .topLeading) {
                                if personalNote.isEmpty {
                                    Text("The reason you cloned this…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
```

- [ ] **Step 3: Save it**

In `saveChanges()`, after `project.notes = notes.trimmingCharacters(in: .whitespaces)`, add:

```swift
        project.personalNote = personalNote.trimmingCharacters(in: .whitespaces)
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add OpenSourceShelf/Views/EditProjectSheet.swift
git commit --only OpenSourceShelf/Views/EditProjectSheet.swift -m "Round-trip personalNote in the Edit sheet

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: End-to-end verification

**Files:** none created; run the app and exercise the flows (use the `verify` skill if available).

- [ ] **Step 1: Launch the built app**

```bash
xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -configuration Debug build 2>&1 | grep -m1 "BUILD SUCCEEDED"
open "$(xcodebuild -project OpenSourceShelf.xcodeproj -scheme 'OpenSource Shelf' -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/OpenSource Shelf.app"
```

Expected: app launches and the existing catalog loads (migration succeeded — projects list is not empty).

- [ ] **Step 2: Verify the inspector flow**

Select any project → inspector shows a dimmed collapsed `▸ Why I saved this` row → expand → type a note → collapse → quit and relaunch the app → the note is still there (autosave persisted it).

- [ ] **Step 3: Verify search**

Type a distinctive word from the note into the app's search field. Expected: that project appears in results.

- [ ] **Step 4: Verify capture + edit + settings**

- Quick Capture (⌘-based capture or toolbar): paste a repo URL → after fetch, a "Why" field sits under Shelf/Category → fill it → Save → the new project's inspector shows the note.
- Edit sheet on any project: "Why I Saved This" field shows the current note; change it; Save; inspector reflects the change.
- Settings → inspector sections list: "Why I Saved This" row exists; toggling it off hides the section in the inspector; toggle back on.

- [ ] **Step 5: Confirm no AI path writes the field**

Run: `grep -rn "personalNote" OpenSourceShelf --include="*.swift" | grep -iv "InspectView\|EditProjectSheet\|QuickCaptureSheet\|ToolProject\|AppSettings"`
Expected: no output (only the five planned files reference it; in QuickCaptureSheet.swift confirm `applySuggestion`/capture-assist code does not mention `personalNote`).

- [ ] **Step 6: Update docs and close out**

If `docs/` release/feature docs track features (e.g. a features list), add one line for the personal note; commit with:

```bash
git commit --only <doc paths> -m "Document the Why I Saved This personal note

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
