# Folders for the Shelf — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user group projects into folders they create — "everything I cloned for project X" — and see them as an expandable section in the sidebar.

**Architecture:** A new `CatalogFolder` SwiftData model plus a `folderID: UUID?` on `ToolProject`. Sidebar selection widens from `SidebarItem?` to a `ShelfSelection` enum wrapping `.builtin(SidebarItem)` and `.folder(UUID)`, so `SidebarItem` stays a closed `CaseIterable` set and no second source of truth appears. Filtering stays a `Predicate<ToolProject>`, matching every other sidebar row.

**Tech Stack:** Swift 5 / SwiftUI, SwiftData, Xcode project with manual `.pbxproj` edits (no `Package.swift`, no file-system-synchronized groups).

**Spec:** `docs/superpowers/specs/2026-07-28-clone-folders-design.md`

## Global Constraints

- **This ships as a BETA and must not reach `main` or the update feed.** Work stays on `claude/clone-folders`. Task 8 publishes a GitHub **pre-release** and deliberately does **not** run `scripts/appcast.sh`. Neither Mac auto-updates to it; stable users see nothing.
- **Version for the beta:** `1.9.0-beta.1`, `CFBundleVersion` 15. Do not bump `main`.
- **One folder per project, at most.** `folderID` is a single optional value, never an array.
- **Deleting a folder ungroups only.** It must never delete, unshelve, unclone, or otherwise alter a project. This is the single most important behaviour in the plan.
- **Folders may hold any project**, cloned or not. Uncloning must not clear `folderID`.
- **Flat only.** No parent/child, no nesting, no recursive counts.
- **`SidebarItem` gains no new cases.** It stays `CaseIterable`; `allCases` and `sidebarCategoryItems` build menus from it.
- **Signing identity** (only if a build is signed): pin the hash `ADC1CB6085203C50EB344490FD8FC03345838EFB` — the Keychain holds two identical Developer ID certs and name lookup fails as ambiguous. Notary profile `reshelf-notary`. Scheme is `OpenSource Shelf`; product is `reshelf.app`.
- **This project has no XCTest target.** Do not add one. Every verification below is a real command whose output is checked, or a described interaction with the running app. Follow it literally rather than substituting unit tests.
- **New Swift files must be registered in `OpenSourceShelf.xcodeproj/project.pbxproj` by hand** — PBXFileReference + group children + PBXBuildFile + Sources phase. A file on disk alone will not compile. Existing ids are 24–26 chars; match that width when generating new ones.
- **Schema hazard:** this adds a model and a field. Once a build migrates `~/reshelf/catalog.store`, opening an older reshelf can migrate it backwards and drop both. Back the store up before first run (Task 2 Step 1) and do not open `/Applications/reshelf.app` while testing the beta.

## Sequencing note — read before starting

`sidebarSelection` has ~40 call sites, and **about twelve of them reference Labs items** (`.compare`, `.ecosystems`, `.workflows`, `.myStack`, `.queue`) in `ContentView.swift`. The paused branch `claude/remove-labs` deletes those surfaces.

**Doing the Labs removal first would delete roughly a third of the call sites this plan has to convert**, and avoid converting code that is about to be thrown away. If that branch is still open when this starts, finish it first. If it has been abandoned, proceed — the conversions below cover the Labs cases too.

## File structure

| File | Responsibility |
|---|---|
| `OpenSourceShelf/Models/CatalogFolder.swift` *(new)* | The `@Model` and nothing else. |
| `OpenSourceShelf/Models/ShelfSelection.swift` *(new)* | The selection enum + conveniences (`builtinItem`, `folderID`). |
| `OpenSourceShelf/Services/CatalogFolderService.swift` *(new)* | Create / rename / delete / assign. All folder mutations live here so the delete-ungroups-only rule has exactly one implementation. |
| `OpenSourceShelf/Views/SidebarView.swift` | The Folders section and its rows. |
| `OpenSourceShelf/Views/ProjectListView.swift` | Filter by folder; the Add to Folder context submenu. |
| `OpenSourceShelf/Views/ContentView.swift` | Selection type conversion (largest diff). |
| `OpenSourceShelf/Views/InspectView.swift` | The Folder row beside Added / Updated. |
| `OpenSourceShelf/Services/CatalogExportService.swift` | Folder DTOs so grouping survives a trip between Macs. |
| `OpenSourceShelf/Services/CatalogImportService.swift` | Name-based folder matching on import. |

---

### Task 1: The model and the selection type

Two small files with no dependents yet, so they can land and compile before anything uses them.

**Files:**
- Create: `OpenSourceShelf/Models/CatalogFolder.swift`
- Create: `OpenSourceShelf/Models/ShelfSelection.swift`
- Modify: `OpenSourceShelf/Models/ToolProject.swift` (add `folderID`, and the init parameter)
- Modify: `OpenSourceShelf/OpenSourceShelfApp.swift:138` (register the model)
- Modify: `OpenSourceShelf.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces: `CatalogFolder` (`id: UUID`, `name: String`, `createdAt: Date`, `sortIndex: Int`); `ToolProject.folderID: UUID?`; and
  ```swift
  enum ShelfSelection: Hashable {
      case builtin(SidebarItem)
      case folder(UUID)
      var builtinItem: SidebarItem? { get }   // nil for .folder
      var folderID: UUID? { get }             // nil for .builtin
  }
  ```
  Every later task uses these exact names.

- [ ] **Step 1: Write `CatalogFolder.swift`**

```swift
import Foundation
import SwiftData

/// A grouping the user makes — "everything I cloned for project X".
///
/// Deliberately *not* a category (those are a fixed taxonomy describing what a
/// repo is) and not a shelf (that says how much you value it). A project belongs
/// to at most one folder, and a folder holds any project whether or not it's
/// cloned — uncloning must not eject a repo from the group that exists to make
/// the cleanup possible.
@Model
final class CatalogFolder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    /// Manual ordering in the sidebar. Ties break on name.
    var sortIndex: Int = 0

    init(name: String, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }
}
```

- [ ] **Step 2: Write `ShelfSelection.swift`**

```swift
import Foundation

/// What the project list is currently showing.
///
/// `SidebarItem` is a `String`-backed `CaseIterable` enum — a closed set, and
/// several menus are built from `allCases`. Folders are created at runtime, so
/// they cannot be cases of it. Wrapping both in one type keeps `SidebarItem`
/// closed while making it impossible for the app to hold two different answers
/// to "what is the list filtered by" at once.
enum ShelfSelection: Hashable {
    case builtin(SidebarItem)
    case folder(UUID)

    var builtinItem: SidebarItem? {
        if case let .builtin(item) = self { return item }
        return nil
    }

    var folderID: UUID? {
        if case let .folder(id) = self { return id }
        return nil
    }
}
```

- [ ] **Step 3: Add `folderID` to `ToolProject`**

After the `lastUpdatedDate` property, add:

```swift
    /// The folder this project belongs to, if any. A plain id rather than a
    /// SwiftData relationship: membership is one-directional, and a relationship
    /// would make deleting a folder a cascade decision instead of a field being
    /// cleared — which is exactly the behaviour we must not have.
    var folderID: UUID?
```

Then add `folderID: UUID? = nil,` to the initializer's parameter list (after `lastUpdatedDate`) and `self.folderID = folderID` to its body (after `self.lastUpdatedDate = lastUpdatedDate`).

- [ ] **Step 4: Register the model in the schema**

In `OpenSourceShelfApp.swift`, change line 138 from:

```swift
            let schema = Schema([ToolProject.self, AppSettings.self])
```

to:

```swift
            let schema = Schema([ToolProject.self, AppSettings.self, CatalogFolder.self])
```

- [ ] **Step 5: Register both new files in the Xcode project**

Add a PBXFileReference, a group-children entry, a PBXBuildFile and a Sources-phase entry for each, mirroring the existing `CatalogImportService.swift` entries. Use ids `F0LDER0001234567890ABCD` / `F0LDER0002234567890ABCD` for `CatalogFolder.swift` and `F0LDER0003234567890ABCD` / `F0LDER0004234567890ABCD` for `ShelfSelection.swift`. Paths are `OpenSourceShelf/Models/CatalogFolder.swift` and `OpenSourceShelf/Models/ShelfSelection.swift`.

- [ ] **Step 6: Verify the project file and build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
plutil -lint OpenSourceShelf.xcodeproj/project.pbxproj
bash build.sh 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `OK`, then `** BUILD SUCCEEDED **`. Ignore SourceKit "Cannot find type" diagnostics — only the build result matters.

- [ ] **Step 7: Confirm both files actually compiled**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
find .build/DerivedData -name "CatalogFolder.o" -o -name "ShelfSelection.o" | head -2
```

Expected: both object files listed. If empty, the pbxproj registration silently failed — a file on disk that isn't in the Sources phase compiles to nothing and produces no error.

- [ ] **Step 8: Commit**

```bash
git add OpenSourceShelf/Models/CatalogFolder.swift OpenSourceShelf/Models/ShelfSelection.swift \
        OpenSourceShelf/Models/ToolProject.swift OpenSourceShelf/OpenSourceShelfApp.swift \
        OpenSourceShelf.xcodeproj/project.pbxproj
git commit -m "Add CatalogFolder model and ShelfSelection"
```

---

### Task 2: The folder service

Every mutation lives here, so "deleting a folder ungroups only" has one implementation to get right and one place to check.

**Files:**
- Create: `OpenSourceShelf/Services/CatalogFolderService.swift`
- Modify: `OpenSourceShelf.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CatalogFolder`, `ToolProject.folderID` from Task 1.
- Produces:
  ```swift
  enum CatalogFolderService {
      static func folders(in context: ModelContext) -> [CatalogFolder]
      @discardableResult static func create(name: String, in context: ModelContext) -> CatalogFolder?
      static func rename(_ folder: CatalogFolder, to name: String, in context: ModelContext)
      static func delete(_ folder: CatalogFolder, in context: ModelContext) -> Int   // count ungrouped
      static func assign(_ project: ToolProject, to folder: CatalogFolder?, in context: ModelContext)
      static func projectCount(for folder: CatalogFolder, in context: ModelContext) -> Int
      static func projects(in folder: CatalogFolder, context: ModelContext) -> [ToolProject]
  }
  ```
  Tasks 3–6 call these exact signatures.

- [ ] **Step 1: Back up the catalog before anything writes to it**

This is the first task that can touch real data. Do it before running any build that opens the store.

```bash
mkdir -p ~/_KIKA_MAIN/_INFRA/backups/reshelf-pre-folders
osascript -e 'tell application "reshelf" to quit' 2>/dev/null; sleep 3; pkill -x reshelf 2>/dev/null
cp ~/reshelf/catalog.store* ~/_KIKA_MAIN/_INFRA/backups/reshelf-pre-folders/
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZTOOLPROJECT;"
```

Expected: three files copied, and a project count printed. Note that number — later steps compare against it.

- [ ] **Step 2: Write the service**

```swift
import Foundation
import SwiftData

/// Every folder mutation goes through here.
///
/// The rule that matters: `delete` clears membership and removes the folder. It
/// must never touch a project's shelf, clone, notes or anything else. Deleting a
/// container does not delete its contents.
enum CatalogFolderService {

    static func folders(in context: ModelContext) -> [CatalogFolder] {
        let all = (try? context.fetch(FetchDescriptor<CatalogFolder>())) ?? []
        return all.sorted {
            $0.sortIndex == $1.sortIndex
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.sortIndex < $1.sortIndex
        }
    }

    /// Creates a folder, or returns the existing one when the name is already
    /// taken — case-insensitively, so "Photos" and "photos" are one folder.
    /// Returns nil for a blank name.
    @discardableResult
    static func create(name: String, in context: ModelContext) -> CatalogFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = folders(in: context).first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return existing
        }
        let next = (folders(in: context).map(\.sortIndex).max() ?? -1) + 1
        let folder = CatalogFolder(name: trimmed, sortIndex: next)
        context.insert(folder)
        try? context.save()
        return folder
    }

    static func rename(_ folder: CatalogFolder, to name: String, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        try? context.save()
    }

    /// Removes the folder and clears membership. Returns how many projects were
    /// ungrouped, so the caller can say so before and after.
    @discardableResult
    static func delete(_ folder: CatalogFolder, in context: ModelContext) -> Int {
        let members = projects(in: folder, context: context)
        for project in members {
            project.folderID = nil          // and nothing else
        }
        context.delete(folder)
        try? context.save()
        return members.count
    }

    /// Pass nil to remove a project from whatever folder it's in.
    static func assign(_ project: ToolProject, to folder: CatalogFolder?, in context: ModelContext) {
        project.folderID = folder?.id
        try? context.save()
    }

    static func projects(in folder: CatalogFolder, context: ModelContext) -> [ToolProject] {
        let id = folder.id
        let descriptor = FetchDescriptor<ToolProject>(
            predicate: #Predicate { $0.folderID == id },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func projectCount(for folder: CatalogFolder, in context: ModelContext) -> Int {
        let id = folder.id
        let descriptor = FetchDescriptor<ToolProject>(predicate: #Predicate { $0.folderID == id })
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
```

- [ ] **Step 3: Register the file in the Xcode project**

Add the four pbxproj entries as in Task 1 Step 5, with ids `F0LDER0005234567890ABCD` / `F0LDER0006234567890ABCD` and path `OpenSourceShelf/Services/CatalogFolderService.swift`.

- [ ] **Step 4: Build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
plutil -lint OpenSourceShelf.xcodeproj/project.pbxproj
bash build.sh 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `OK`, `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Confirm the schema migrated without loss**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
open .build/reshelf.app && sleep 10
osascript -e 'tell application "reshelf" to quit'; sleep 4; pkill -x reshelf 2>/dev/null
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZTOOLPROJECT;"
sqlite3 -readonly ~/reshelf/catalog.store "pragma table_info(ZTOOLPROJECT);" | grep -i folderid
sqlite3 -readonly ~/reshelf/catalog.store ".tables" | tr ' ' '\n' | grep -i folder
```

Expected: the same project count as Step 1, a `ZFOLDERID` column, and a `ZCATALOGFOLDER` table. **If the count dropped, stop and restore from the Step 1 backup.**

- [ ] **Step 6: Commit**

```bash
git add OpenSourceShelf/Services/CatalogFolderService.swift OpenSourceShelf.xcodeproj/project.pbxproj
git commit -m "Add CatalogFolderService — create, rename, delete, assign"
```

---

### Task 3: Convert the selection type

The broad, mechanical task. Nothing new works afterwards; it just compiles again with the wider type, which unblocks Tasks 4–6.

**Files:**
- Modify: `OpenSourceShelf/Views/ContentView.swift` (~30 sites)
- Modify: `OpenSourceShelf/Views/ProjectListView.swift` (7 sites)
- Modify: `OpenSourceShelf/Views/SidebarView.swift:21`
- Modify: `OpenSourceShelf/Views/Components/CollapsedSidebarRail.swift:5`

**Interfaces:**
- Consumes: `ShelfSelection` from Task 1.
- Produces: `sidebarSelection` typed `ShelfSelection?` throughout; `SidebarView` and `CollapsedSidebarRail` take `@Binding var selection: ShelfSelection?`.

- [ ] **Step 1: Change the declarations**

Four declaration sites:

- `ContentView.swift:93` — `@State private var sidebarSelection: ShelfSelection? = .builtin(.allProjects)`
- `ContentView.swift:660` — `@Binding var sidebarSelection: ShelfSelection?`
- `ProjectListView.swift:8` — `@Binding var sidebarSelection: ShelfSelection?`
- `SidebarView.swift:21` — `@Binding var selection: ShelfSelection?`
- `CollapsedSidebarRail.swift:5` — `@Binding var selection: ShelfSelection?`

- [ ] **Step 2: Build to get the complete list of breaks**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
bash build.sh 2>&1 | grep -oE "OpenSourceShelf/[A-Za-z/]+\.swift:[0-9]+:[0-9]+: error: .*" | sort -u
```

Expected: a list of errors. **This list is the task** — the compiler enumerates every site, which is precisely why the type changed shape rather than a parallel field being added.

- [ ] **Step 3: Convert every assignment and comparison**

Apply these transformations. `X` stands for any `SidebarItem` case.

| Before | After |
|---|---|
| `sidebarSelection = .X` | `sidebarSelection = .builtin(.X)` |
| `sidebarSelection == .X` | `sidebarSelection == .builtin(.X)` |
| `sidebarSelection?.title` | `sidebarSelection?.builtinItem?.title` |
| `sidebarSelection?.isCatalogFilter` | `sidebarSelection?.builtinItem?.isCatalogFilter` |
| `sidebarSelection.requiresLabs` | `sidebarSelection.builtinItem?.requiresLabs == true` |
| `switch sidebarSelection {` over `SidebarItem` cases | `switch sidebarSelection?.builtinItem {` |
| `sidebarSelection = item` *(where `item: SidebarItem`)* | `sidebarSelection = .builtin(item)` |

For `ContentView.swift:382` and `:442`, both `switch sidebarSelection {`, switch on `sidebarSelection?.builtinItem` and add a `default: EmptyView()` (or the existing fallback) so a `.folder` selection falls through rather than failing to compile.

- [ ] **Step 4: Handle the empty-state text for folders**

`ProjectListView.swift:873-874` reads:

```swift
        if let sidebarSelection, sidebarSelection.isCatalogFilter {
            return "No projects in \(sidebarSelection.title)"
```

Replace with:

```swift
        if let item = sidebarSelection?.builtinItem, item.isCatalogFilter {
            return "No projects in \(item.title)"
        }
        if sidebarSelection?.folderID != nil {
            return "This folder is empty"
        }
```

- [ ] **Step 5: Build until clean**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
bash build.sh 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `** BUILD SUCCEEDED **`. Repeat Step 3 for any remaining errors.

- [ ] **Step 6: Confirm nothing regressed in the running app**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
open .build/reshelf.app && sleep 9
```

Click through All Projects, Top Shelf, The Collector, Yard Sale, Cloned and three category rows. Each must filter the list as before and show the right count. Then quit.

- [ ] **Step 7: Commit**

```bash
git add OpenSourceShelf/Views/ContentView.swift OpenSourceShelf/Views/ProjectListView.swift \
        OpenSourceShelf/Views/SidebarView.swift OpenSourceShelf/Views/Components/CollapsedSidebarRail.swift
git commit -m "Widen sidebar selection to ShelfSelection"
```

---

### Task 4: The Folders section in the sidebar

**Files:**
- Modify: `OpenSourceShelf/Views/SidebarView.swift` (section after Library, before Categories; `SidebarSection` at `Models/SidebarItem.swift:266`)
- Modify: `OpenSourceShelf/Models/SidebarItem.swift:266-270` (add the section title)

**Interfaces:**
- Consumes: `CatalogFolderService.folders(in:)`, `.projectCount(for:in:)`, `.projects(in:context:)`, `ShelfSelection.folder(UUID)`.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add the section title**

In `SidebarItem.swift`, extend `SidebarSection`:

```swift
enum SidebarSection: String {
    case library = "Library"
    case folders = "Folders"
    case categories = "Categories"
    case settings = "Settings"
}
```

- [ ] **Step 2: Add the section to `SidebarView`**

`SidebarView` needs the context and the folder list. Add near its other properties:

```swift
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogFolder.sortIndex) private var folders: [CatalogFolder]
```

Then between the Library `Section` and the Categories `Section` (after the closing brace of Library, around line 51):

```swift
                // Only when folders exist — an empty heading is noise on a fresh
                // install, and folders are opt-in by nature.
                if !folders.isEmpty {
                    Section(SidebarSection.folders.rawValue) {
                        ForEach(folders) { folder in
                            DisclosureGroup {
                                ForEach(CatalogFolderService.projects(in: folder, context: modelContext)) { project in
                                    Text(project.name)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                        .frame(width: 20)
                                        .font(.system(size: 13))
                                    Text(folder.name)
                                    Spacer()
                                    Text("\(CatalogFolderService.projectCount(for: folder, in: modelContext))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(ShelfSelection.folder(folder.id))
                            .contextMenu {
                                Button("Rename…") { renameTarget = folder }
                                Button("Delete Folder…") { deleteTarget = folder }
                            }
                        }
                    }
                }
```

- [ ] **Step 3: Add the rename and delete state and sheets**

Add to `SidebarView`'s properties:

```swift
    @State private var renameTarget: CatalogFolder?
    @State private var deleteTarget: CatalogFolder?
    @State private var draftName = ""
```

And attach to the `List` (after `.contentMargins`):

```swift
            .alert("Rename Folder", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $draftName)
                Button("Rename") {
                    if let folder = renameTarget {
                        CatalogFolderService.rename(folder, to: draftName, in: modelContext)
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .onChange(of: renameTarget) { _, folder in
                draftName = folder?.name ?? ""
            }
            .alert("Delete Folder?", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("Delete Folder", role: .destructive) {
                    if let folder = deleteTarget {
                        CatalogFolderService.delete(folder, in: modelContext)
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                if let folder = deleteTarget {
                    Text("\(CatalogFolderService.projectCount(for: folder, in: modelContext)) project(s) will no longer be grouped. Nothing is deleted — they keep their shelf, their clone and their notes.")
                }
            }
```

- [ ] **Step 4: Build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
bash build.sh 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify the section only appears when folders exist**

Launch the app. With no folders yet, there must be **no** Folders heading between Library and Categories.

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZCATALOGFOLDER;"
```

Expected: `0`, and no heading on screen.

- [ ] **Step 6: Commit**

```bash
git add OpenSourceShelf/Views/SidebarView.swift OpenSourceShelf/Models/SidebarItem.swift
git commit -m "Sidebar: Folders section with counts, rename and delete"
```

---

### Task 5: Assigning projects, and filtering by folder

The task that makes folders usable — creating one, putting things in it, and seeing only those things.

**Files:**
- Modify: `OpenSourceShelf/Views/ProjectListView.swift` (`catalogContextMenu(for:)` at :287, and the filter at :830)
- Modify: `OpenSourceShelf/Views/InspectView.swift` (after the Updated row, ~:135)

**Interfaces:**
- Consumes: `CatalogFolderService`, `ShelfSelection.folderID`.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Filter the list by the selected folder**

`ProjectListView.swift:830` currently reads:

```swift
        guard let selection = sidebarSelection, selection.isCatalogFilter else { return projects }
```

After Task 3 it is `selection.builtinItem?.isCatalogFilter`. Add the folder case immediately before it:

```swift
        if let folderID = sidebarSelection?.folderID {
            return projects.filter { $0.folderID == folderID }
        }
```

- [ ] **Step 2: Add the Add to Folder submenu**

Inside `catalogContextMenu(for:)`, add:

```swift
        Menu("Add to Folder") {
            ForEach(CatalogFolderService.folders(in: modelContext)) { folder in
                Button {
                    CatalogFolderService.assign(project, to: folder, in: modelContext)
                } label: {
                    if project.folderID == folder.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            if !CatalogFolderService.folders(in: modelContext).isEmpty {
                Divider()
            }
            Button("New Folder…") {
                newFolderProject = project
                newFolderName = ""
            }
            if project.folderID != nil {
                Divider()
                Button("Remove from Folder") {
                    CatalogFolderService.assign(project, to: nil, in: modelContext)
                }
            }
        }
```

- [ ] **Step 3: Add the New Folder prompt**

Add to `ProjectListView`'s properties:

```swift
    @State private var newFolderProject: ToolProject?
    @State private var newFolderName = ""
```

And attach to the list body:

```swift
        .alert("New Folder", isPresented: Binding(
            get: { newFolderProject != nil },
            set: { if !$0 { newFolderProject = nil } }
        )) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                if let project = newFolderProject,
                   let folder = CatalogFolderService.create(name: newFolderName, in: modelContext) {
                    CatalogFolderService.assign(project, to: folder, in: modelContext)
                }
                newFolderProject = nil
            }
            Button("Cancel", role: .cancel) { newFolderProject = nil }
        }
```

- [ ] **Step 4: Show the folder in the inspector**

In `InspectView.swift`, after the `if let updated = project.lastUpdatedDate { … }` block, add:

```swift
                    if let folderID = project.folderID,
                       let folder = (try? modelContext.fetch(FetchDescriptor<CatalogFolder>()))?
                           .first(where: { $0.id == folderID }) {
                        HStack {
                            Text("Folder")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(folder.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
```

- [ ] **Step 5: Build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
bash build.sh 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Exercise it end to end**

Launch the app. Right-click a project → Add to Folder → New Folder… → name it `Test A`. Repeat for a second project into `Test A`, and a third into a new `Test B`.

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
sqlite3 -readonly ~/reshelf/catalog.store \
  "select f.ZNAME, count(p.Z_PK) from ZCATALOGFOLDER f
     left join ZTOOLPROJECT p on p.ZFOLDERID = f.ZID group by f.ZNAME;"
```

Expected: `Test A|2` and `Test B|1`. Then click each folder in the sidebar and confirm the list shows exactly those projects, and the inspector shows a Folder row.

- [ ] **Step 7: Verify delete ungroups and nothing more — the critical test**

Note a member's shelf, clone badge and notes first. Then right-click `Test A` in the sidebar → Delete Folder… → confirm.

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZCATALOGFOLDER where ZNAME='Test A';"
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZTOOLPROJECT;"
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZTOOLPROJECT where ZFOLDERID is not null;"
```

Expected: `0` folders named Test A; the **same total project count** as Task 2 Step 1; and only `Test B`'s single member still grouped. Confirm in the app that the ex-members kept their shelf, clone badge and notes.

- [ ] **Step 8: Commit**

```bash
git add OpenSourceShelf/Views/ProjectListView.swift OpenSourceShelf/Views/InspectView.swift
git commit -m "Assign projects to folders, and filter the list by folder"
```

---

### Task 6: Carry folders through export and import

Without this, importing on the second Mac silently drops every grouping — the same gap `personalNote` and `lastUpdatedDate` each had.

**Files:**
- Modify: `OpenSourceShelf/Services/CatalogExportService.swift`
- Modify: `OpenSourceShelf/Services/CatalogImportService.swift`

**Interfaces:**
- Consumes: `CatalogFolder`, `CatalogFolderService.create(name:in:)`.
- Produces: `CatalogFolderDTO` (`id: String`, `name: String`, `createdAt: Date`, `sortIndex: Int`); `CatalogProjectDTO.folderID: String?`; `CatalogSnapshotDTO.folders: [CatalogFolderDTO]?`.

- [ ] **Step 1: Add the DTOs**

In `CatalogExportService.swift`, add above `CatalogSnapshotDTO`:

```swift
/// A folder in an exported catalog. Optional in the snapshot, so exports written
/// before folders existed still decode.
struct CatalogFolderDTO: Codable {
    var id: String
    var name: String
    var createdAt: Date
    var sortIndex: Int

    init(_ folder: CatalogFolder) {
        id = folder.id.uuidString
        name = folder.name
        createdAt = folder.createdAt
        sortIndex = folder.sortIndex
    }
}
```

Add to `CatalogProjectDTO`, beside `lastUpdatedDate`:

```swift
    /// Optional for the same reason as `personalNote`: exports predating folders
    /// have no key for it.
    var folderID: String?
```

Set it in `init(_ p: ToolProject)`: `folderID = p.folderID?.uuidString`.

Add to `CatalogSnapshotDTO`: `var folders: [CatalogFolderDTO]?`.

- [ ] **Step 2: Encode folders**

Change `encode(_ projects:)` to accept them, and update the two callers (`presentExportPanel` and `CatalogBackupService.writeSnapshot`) to pass the folder list:

```swift
    static func encode(_ projects: [ToolProject],
                       folders: [CatalogFolder] = []) throws -> Data {
        let payload = CatalogSnapshotDTO(
            exportedAt: Date(),
            app: "reshelf",
            version: 1,
            projectCount: projects.count,
            projects: projects.map(CatalogProjectDTO.init),
            folders: folders.isEmpty ? nil : folders.map(CatalogFolderDTO.init)
        )
        return try makeEncoder().encode(payload)
    }
```

- [ ] **Step 3: Add a folders accessor to decode**

```swift
    /// Folders from a snapshot, empty for exports written before they existed.
    static func decodeFolders(_ data: Data) throws -> [CatalogFolderDTO] {
        try makeDecoder().decode(CatalogSnapshotDTO.self, from: data).folders ?? []
    }
```

- [ ] **Step 4: Match folders by name on import**

In `CatalogImportService.apply(_:updatingExisting:into:)`, before inserting projects:

```swift
        // Match by name, case-insensitively — not by id. Two Macs that each made
        // a "Photos app" folder should converge on one, whereas id-matching would
        // duplicate every folder on the second machine.
        var folderIDMap: [String: UUID] = [:]
        for dto in plan.folders {
            if let local = CatalogFolderService.create(name: dto.name, in: context) {
                folderIDMap[dto.id] = local.id
            }
        }
```

Then when building each project, remap: `project.folderID = row.folderID.flatMap { folderIDMap[$0] }`.

Add `let folders: [CatalogFolderDTO]` to `CatalogImportService.Plan`, populated in `plan(rows:sourceURL:context:)` from `decodeFolders`. `presentOpenPanel` returns the folders alongside the rows.

- [ ] **Step 5: Build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
bash build.sh 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Verify the round trip carries folders**

Launch, export via ⇧⌘E to `~/reshelf/backups/folder-test.json`, then:

```bash
python3 -c "
import json; d=json.load(open('/Users/kika_hub/reshelf/backups/folder-test.json'))
print('folders:', [f['name'] for f in (d.get('folders') or [])])
print('grouped projects:', sum(1 for p in d['projects'] if p.get('folderID')))
"
```

Expected: the folder names you created, and a non-zero grouped count.

- [ ] **Step 7: Verify a pre-folders export still imports**

```bash
ls -t ~/reshelf/backups/catalog-*.json | tail -1
```

Import that file (⇧⌘I) with *Also update the projects I already have* **off**. It must succeed, report `0 added`, and leave existing folder assignments untouched:

```bash
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZTOOLPROJECT where ZFOLDERID is not null;"
```

Expected: unchanged from Step 6.

- [ ] **Step 8: Commit**

```bash
git add OpenSourceShelf/Services/CatalogExportService.swift OpenSourceShelf/Services/CatalogImportService.swift
git commit -m "Carry folders through export and import, matching by name"
```

---

### Task 7: Documentation

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `todo.md`
- Modify: `future-features.md`

- [ ] **Step 1: Add the changelog entry**

Insert above the most recent released version heading:

```markdown
## [1.9.0-beta.1] — unreleased

### Added
- **Folders.** Group projects into folders you make — "everything I cloned for the
  photos app" — and they appear as their own section in the sidebar, each one
  expandable to show what's inside. A project belongs to one folder at most, and a
  folder can hold anything on your shelf whether or not it's cloned, so uncloning
  something doesn't drop it out of the group.
- Deleting a folder only ungroups. Every project keeps its shelf, its clone and its
  notes — the folder stops existing, nothing else changes.
- Folders travel in your exported catalog, and importing matches them by name, so
  two Macs that each made a "Photos app" folder end up with one rather than two.
```

- [ ] **Step 2: Tick the todo entries**

In `future-features.md`, mark the "Folders for clones, as a sidebar tree" bullet `[x]` with `— shipped in 1.9.0-beta.1`. Leave the multi-select bullet unticked; it is a separate spec.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md todo.md future-features.md
git commit -m "Docs: folders in 1.9.0-beta.1"
```

---

### Task 8: Ship as a beta — NOT to main, NOT to the update feed

Read this whole task before running anything. The point is that neither of Kika's Macs learns this version exists.

**Files:**
- Modify: `OpenSourceShelf/Info.plist` (version only)

- [ ] **Step 1: Confirm you are on the branch and `main` is untouched**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git branch --show-current
git log --oneline main -1
```

Expected: `claude/clone-folders`, and `main` still at the last stable release commit. **If the branch says `main`, stop and move the work to a branch.**

- [ ] **Step 2: Set the beta version**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.9.0-beta.1' \
                        -c 'Set :CFBundleVersion 15' OpenSourceShelf/Info.plist
git add OpenSourceShelf/Info.plist
git commit -m "Version 1.9.0-beta.1"
```

- [ ] **Step 3: Build the signed, notarized artifacts**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
RESHELF_SIGN_IDENTITY=ADC1CB6085203C50EB344490FD8FC03345838EFB bash scripts/release.sh
```

Expected: two `status: Accepted` results and both artifacts listed. ~15 minutes.

- [ ] **Step 4: Push the branch and cut a PRE-release**

Note `--prerelease`, and the absence of `--latest`. Without both, the release page would present this as the current version to everyone.

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git push -u origin claude/clone-folders
git tag v1.9.0-beta.1 && git push origin v1.9.0-beta.1
gh release create v1.9.0-beta.1 \
  --title "reshelf 1.9.0-beta.1 (beta)" \
  --prerelease \
  --target claude/clone-folders \
  --notes "Beta — folders for the shelf. Install by hand; this is deliberately not offered through in-app updates.

Adds folders as a sidebar section, one folder per project, and carries them through export/import.

⚠️ Adds a field and a model to the catalog store. After installing this, do not open an older reshelf build — it can migrate the store backwards and drop them. Back up ~/reshelf/catalog.store first." \
  .build/dist/reshelf-1.9.0-beta.1.dmg
```

- [ ] **Step 5: Do NOT publish the appcast — and prove it**

**Do not run `scripts/appcast.sh`.** Running it would put the beta in the live feed and both Macs would offer it.

```bash
curl -s "https://aka-kika.github.io/reshelf/appcast.xml?bust=$(date +%s)" \
  | grep -oE "shortVersionString>[^<]+"
```

Expected: the **stable** version, not `1.9.0-beta.1`. If the beta appears, the feed was published by mistake — regenerate it from `main` and push before anything auto-updates.

- [ ] **Step 6: Install the beta by hand, on one Mac only**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
cp ~/reshelf/catalog.store* ~/_KIKA_MAIN/_INFRA/backups/reshelf-pre-folders/ 2>/dev/null
osascript -e 'quit app "reshelf"'; sleep 3; pkill -x reshelf
MNT=$(hdiutil attach .build/dist/reshelf-1.9.0-beta.1.dmg -nobrowse -noautoopen | grep -o '/Volumes/.*' | head -1)
rm -rf /Applications/reshelf.app && cp -R "$MNT/reshelf.app" /Applications/reshelf.app
hdiutil detach "$MNT"; open /Applications/reshelf.app
```

Note that the installed app now *is* the beta, so **in-app Check for Updates will offer to "update" it back down to the stable release.** That's expected: the feed only knows about stable. Don't accept it while testing.

- [ ] **Step 7: Leave `main` alone**

Do not merge. When the beta has been lived with and folders feel right, a later session bumps to `1.9.0`, merges, releases normally, and *then* runs `scripts/appcast.sh` so both Macs get it through Sparkle.
