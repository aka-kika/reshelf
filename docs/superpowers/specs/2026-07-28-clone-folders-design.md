# Folders for the shelf — design

**Date:** 2026-07-28 · **Target release:** 1.9.0 · **Status:** approved, not yet implemented

## Problem

Cloning ~100 repos for one project leaves no record that they belonged together.
Afterwards there is no way to see which repos that project needed, and no way to
retire the batch — every one has to be found by memory and dealt with individually.

Categories can't express this: they're a fixed taxonomy (hardcoded in
`SidebarItem.swift`) describing *what a repo is*, not *what you got it for*. Shelf
status can't either — a repo's shelf says how much you value it, and a project's
worth of repos spans all three shelves.

So: a folder is a **user-made grouping**, orthogonal to both.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Membership | **One folder at most** | Stores as one optional field, works directly in a `Predicate`, and "what did I clone for X" stays unambiguous. |
| Eligibility | **Any project**, cloned or not | A folder is "everything for project X", including repos shelved but never cloned. Uncloning must not eject a repo from the group that exists to enable the cleanup. |
| Deleting a folder | **Ungroups only** | Deleting a container never deletes contents. Projects keep their shelf, clone, notes — they simply stop being grouped. |
| Shape | **Flat, expandable** | Folders sit at one level; each expands to list its members. No parent/child model, no recursive counts, no cycle prevention. |
| Selection model | **Widen to `ShelfSelection`** | See below. The only option where the state can't represent a contradiction. |

## Architecture

### The selection type is the crux

`sidebarSelection` is `SidebarItem?` today — a `String`-backed `CaseIterable` enum.
Folders are created at runtime, so they cannot be cases of it. A new type wraps both:

```swift
enum ShelfSelection: Hashable {
    case builtin(SidebarItem)
    case folder(UUID)
}
```

`SidebarItem` is left exactly as it is: still a closed set, still `CaseIterable`, so
`allCases` and `sidebarCategoryItems` keep working for the menus built from them.

Every site comparing selection changes shape once — `sidebarSelection == .compare`
becomes `sidebarSelection == .builtin(.compare)`. Mechanical, and the compiler finds
all of them, which is the point: the two rejected alternatives both left a way for
the app to believe two different things about what the list is showing.

*Rejected:* adding a `.folder(UUID)` case to `SidebarItem` (destroys `CaseIterable`
for a type whose job is being a closed set), and keeping a separate "active folder"
alongside the existing selection (two sources of truth for one question).

### Data model

A new SwiftData model, and one field on the existing one:

```swift
@Model
final class CatalogFolder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    /// Manual ordering in the sidebar; ties break on name.
    var sortIndex: Int = 0
}
```

```swift
// ToolProject
/// The folder this project belongs to, if any. A plain id rather than a
/// relationship: membership is one-directional, and a relationship would make
/// deleting a folder a cascade decision rather than a field being cleared.
var folderID: UUID?
```

Registered as `Schema([ToolProject.self, AppSettings.self, CatalogFolder.self])`.

Filtering stays a `Predicate<ToolProject>`, matching how every other sidebar row
works: `#Predicate { $0.folderID == id }`.

### Sidebar

A third section between Library and Categories, present only when folders exist —
an empty "Folders" heading would be noise on a fresh install:

```
Library      All Projects · Top Shelf · The Collector · Yard Sale · Cloned
Folders      ▸ Photos app        12
             ▸ Terminal research   8
Categories   Database · Backend · AI / Agent · …
```

Each folder row selects (`.folder(id)`) and filters the list, exactly like a
category row. The disclosure triangle expands to list member project names; picking
one selects that project directly. Counts come from the same `counts` object the
other rows use.

### Assigning

- **Row context menu → Add to Folder ▸** lists existing folders, then **New Folder…**
  Choosing a folder assigns; the submenu marks the current one and offers **Remove
  from Folder** when the project already has one.
- **Inspector** shows a **Folder** row next to Added / Updated when set, so
  membership is visible where the rest of a project's facts are.
- **Folder row context menu** → Rename…, Delete. Delete says how many projects will
  be ungrouped, and states that nothing else changes.

### Export / import

Folders travel with the catalog, or importing on the second Mac would silently drop
the grouping — the same gap `personalNote` and `lastUpdatedDate` had.

`CatalogSnapshotDTO` gains `folders: [CatalogFolderDTO]?` (id, name, createdAt,
sortIndex) and `CatalogProjectDTO` gains `folderID: String?`. Both optional, so
older exports still decode.

On import: folders are matched by **name**, case-insensitively, not by id — two Macs
that each created "Photos app" independently should converge on one folder rather
than two identically-named ones. A project's `folderID` is remapped to the local
folder's id. A folder named in the file but absent locally is created.

## Testing

No XCTest target exists, so verification is a real command or driving the app:

1. Build; create two folders; assign several projects to each.
2. `sqlite3 ~/reshelf/catalog.store` — confirm `ZCATALOGFOLDER` rows and
   `ZTOOLPROJECT.ZFOLDERID` values.
3. Select a folder — the list shows exactly its members; counts match.
4. Delete a folder — its projects survive with their shelf, clone and notes intact,
   and `ZFOLDERID` is null. **This is the test that matters most.**
5. Export, then import into a catalog whose folder names differ — confirm matching
   by name converges rather than duplicating.
6. Confirm an import of a **pre-1.9.0** export still succeeds and leaves existing
   folder assignments alone.

## Risks

- **Another schema migration.** This adds a model and a field, so opening an older
  build afterwards can migrate the store backwards and drop both. That trap has
  already cost data once in this project. The release notes must say it, and both
  Macs should be updated together.
- **Every sidebar-selection call site changes.** Mechanical but broad; a missed one
  is a compile error rather than a silent bug, which is why the type changed shape
  instead of gaining a parallel field.
- **Name-matching on import is a judgement call.** Two folders that genuinely mean
  different things but share a name will merge. Matching on id instead would
  duplicate every folder on the second Mac, which is worse and less recoverable.

## Out of scope

Multi-select and batch actions (own spec — most of it doesn't need folders),
nesting, a repo in several folders, and folders as filesystem directories. Clones
keep living under `repos/<Category>/<repo>`; a folder is a label, not a path.
