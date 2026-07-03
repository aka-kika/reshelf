# Quick Capture redesign — "the card moment"

**Date:** 2026-07-03 · **Status:** approved by Kika ("go")
**File touched:** `OpenSourceShelf/Views/QuickCaptureSheet.swift` (layout only; save/fetch logic unchanged)

## Problem

After Fetch, the sheet is a flat wall of identical rounded fields: the description
appears in three places, "Metadata" shows raw `14` / `NOASSERTION` with no context,
the Shelf picker truncates ("The Collec…"), and there's no moment where the repo
feels *captured*. Kika almost never edits anything — she pastes → Enter → Enter —
so ~80% of the visible form is dead weight.

## Design

### 1. Before fetch (unchanged, tightened)
Bolt header · URL field + Fetch. Keyboard path identical: paste → Enter fetches.
The sheet is short in this phase.

### 2. After fetch — repo identity card
The top of the sheet becomes a card (quiet fill, 10pt radius), not a form:

- **Owner avatar** (40pt, `https://github.com/<owner>.png?size=64` via AsyncImage,
  rounded-rect clipped, placeholder fill while loading)
- **Repo name** (17pt semibold) with **owner** underneath (12pt secondary)
- **Fact row:** ★ stars (yellow star, formatted count) · license (SPDX; `NOASSERTION`
  or empty renders as "No license") + existing `LicenseInfoButton` ⓘ popover ·
  language chip when present
- **Description** as readable secondary text (the one and only place it appears)
- **Website link** (small `Link`, only when homepage exists)
- Duplicate warning stays as the existing blue banner, shown under the card.

### 3. The only two decisions, inline under the card
One compact row: **Shelf** (menu picker, `.fixedSize()` — never truncates) and
**Category** (editable text field). This is the whole visible form.

### 4. Everything else → "More details" disclosure, collapsed by default
Name · links (GitHub + website) · short/long description · tags · use cases ·
quick flags · personal fit stars · the AI Suggestions section (Labs). Same
`field()` styling as today, minus the removed duplication: the raw
Stars/License "Metadata" fields are gone (they live on the card; fetched values
are still saved unchanged).

### 5. Behavior guarantees
- Enter still saves once fetched (`handleSubmit` untouched).
- Save/duplicate logic, AI generation, icon fetch: unchanged.
- Sheet height by phase: ~240pt before fetch, ~560pt with card, ~700pt expanded,
  animated. Width stays 520pt.
- Visual language: flat `windowBackgroundColor`, hairline dividers, uppercase
  micro-labels only inside the disclosure.

## Out of scope
Two-step wizard flow, changes to `QuickCaptureService` / `CategoryClassifier`,
the ⌘K palette entry point.
