# reshelf review fixes, 25 Oct 2026

Branch `review-fixes-2026-10-25`, from `main` at `a37bbd2`.
Backup branch `backup/main-2026-10-25` points at that same commit.
Nothing was pushed, merged, tagged, released, or installed.
The app was not opened on this Mac. `~/reshelf` was not touched.

47 fix commits, in two passes. The second pass is the 13 mcode items added at 01:08. 7 Runway items are still open. Logic tests: `bash Tests/run.sh` passed after the second pass.
Build: `xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -destination 'platform=macOS' build` succeeded after the second pass (Debug, arm64).

## Second pass (mcode, added 01:08)

```
ca54d2e Decode a restore preview off the main thread
44fc6f5 Do not replace an unborn checkout when cloning
62200e1 Close git's pipe readers when a command times out
e375c35 Remove the dead normalized-URL step in the metadata lookup
adebc50 Disable Edit Save when the name is only spaces
dbf2c54 Match a compound topic against the whole repo name
4bd27cd Refuse a folder rename that clashes with another folder
546e7a3 Keep every failure when moving several clones to the Trash
7d6ef5e Stop Send to reshelf when the catalog save fails
885b37f Show a failed Send to reshelf reason in the list status line
769ab61 Save Why I saved this through CatalogSave when the field loses focus
bbd3706 Finish the category merge only after the save works
efe2f84 Keep Local-First and Self-Hosted when merging duplicate repos
```

## First pass (`git log --oneline` before the summary note)

```
92454db Remember an emptied shelf in the delete itself
2f5a407 Reveal a repo picked in Search when a filter was hiding it
0724898 Match GitHub metadata by owner and name only
abcca8a Check for a duplicate again after Send to reshelf fetches
0598a5b Clear the note, use cases and flags when Quick Capture fetches another link
abeadca Ignore Return while Quick Capture is still fetching
79b54b1 Read the catalog fresh after a launch restore
57a8ff2 Write a labelled backup before importing GitHub URLs
0b434eb Keep shelf-map.sh inside the clone folder
983dc24 Say when Refresh Info has nothing to refresh because there is no GitHub link
146706e Read a clone's identity from the origin remote only
499cdda Re-fetch a repo before the post-save metadata step reads it
513665d Keep plus and hash in a sidebar tag
73a8e60 Search the GitHub link and the website too
3481b86 Match a sidebar category to the whole name
fb23c47 Allow a GitHub owner or repo named tree or blob
535725d Record an empty folder list in backups that have no folders
9c72212 Treat a GitHub 403 with Retry-After as a rate limit
accdb46 Keep failed GitHub links in the import box
1381172 Stop saying Quick Capture can fetch a README
5bd9617 Make the docs match what the app actually does
5f8e1aa Create a folder on restore only when a restored repo uses it
a08ca1c Leave a file alone when it sits where a clone would go
18b5f0d Show the Capture Assist note on the Quick Capture form
71cfbbf Keep the first clicked row when command-click starts a batch
699fd75 Put back only the shelf, tags, notes and folder
329a8a1 Keep labelled backups when the 30 routine snapshots fill up
5e78901 Skip the category-folder merge when the clone folder is custom
d2f2b69 Write a labelled backup before a batch shelf move or a folder delete
0553d1b Stop a delete or Yard Sale move when the backup cannot be written
32fe15b Open only http and https links from the inspector
c4b871a Back up the catalog after every save, not only when the count changes
79ae888 Keep a repo's name across a clone so a delete cannot crash
b009819 Mark clones reshelf made, and adopt only those
```

`reshelf://add` staying silent was not on this card. It was left as Kika decided on 20 Oct.

## Still open (7)

These were not started. They are still on Runway. None of them is a product decision.

- `e1c5` A clone on another branch shows Updates forever, and Pull switches it to the default branch. Tags are force-fetched before the safety checks. `GitClient.swift`, `CatalogCloneService.swift`. This changes pull. It needs its own pass and the existing pull tests.
- `599e` Import counts a repo as imported when the save failed. Cancel in Edit keeps an unsaved edit. `CatalogImportService.swift`, `ImportURLsSheet.swift`, `EditProjectSheet.swift`.
- `058d` Icons are resized off the main thread with `lockFocus`, and wide icons end up larger than 64 pt. `IconFetcher.swift`.
- `53d5` Every return to the app rescans the clone folder on the main thread. `ContentView.swift`.
- `a48e` The save-failed alert uses `runModal` from async code and can freeze with a sheet open. `CatalogSave.swift`. Showing it as a sheet changes how every save failure looks.
- `5dbc` Refresh Info and the refresh after Pull overwrite a license typed by hand. `RepoInfoRefreshService.swift`. Needs a rule for what "typed by hand" means next to GitHub's "no license".
- `e998` An avatar that fails to load is asked for again on every launch and every count change. `IconFetcher.swift`, `ProjectListView.swift`.

Also worth a look in that VM:

- Rename a folder onto another folder's name, including different capitals. It should refuse.
- Why I saved this: leave the field. A full disk would show the save alert.
- Edit: a name of only spaces cannot be saved.
- Send to reshelf for a link that fails: the list status line says why.
- Move several clones to the Trash when one cannot be moved: every failure is in the status line.
- Restore from Backup: picking a backup does not freeze the window.

## What needs a VM check

Not checked in a VM. Do not check on Kika's screen. Worth a pass in the test VM before install:

- A custom clone folder: an unmarked checkout is not Cloned, Remove Local Clone does not trash it, Pull does not run on it. A clone reshelf makes gets `.git/reshelf-clone` and does count.
- Website row: `file://` and `smb://` do not open. `https://` still does.
- Quick Capture: Notes field is visible. A second fetch clears the note, use cases, and flags. Return during a fetch does not fetch twice.
- Command-click after a plain click: the batch count matches the highlighted rows. Command-T moves all of them.
- Search: typing an owner finds the repo. Picking a result while a category filter is on shows that repo.
- Refresh Info: a shelf whose remaining repos have no GitHub link does not say they are all cloned.
- Delete the last repo and quit immediately: the next launch stays empty.
- Put back changes: shelf, tags, notes, and folder return. Name, link, description, and category stay.
- Import GitHub URLs: a failed link stays in the box. A labelled backup exists before the first insert.
