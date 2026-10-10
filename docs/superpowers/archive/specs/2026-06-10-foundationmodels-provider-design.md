# Apple FoundationModels as a first-class AI provider

Date: 2026-06-10
Status: prototyped

## Goal

Wire Apple's on-device FoundationModels framework (Apple Intelligence) into reshelf as a
real AI provider, so repo intelligence (summary, usefulness, classifications, risks,
scores) and Quick Capture suggestions work with zero setup, no API keys, and no data
leaving the Mac.

## Ideas evaluated

1. **Natural-language search over the shelf** ("that menu-bar app I cloned for global
   hotkeys"). Viable as: AFM parses the query into a structured `SearchIntent`
   (@Generable: keywords, category guess, platform), prefilter via existing substring
   search, AFM reranks the top candidates (pattern proven in the_librarian's
   afm_rerank.swift). Deferred: it is a new parallel feature needing its own UX (an LLM
   in a search-as-you-type box needs an explicit "ask" interaction), and the unused
   embeddings infrastructure (`EmbeddingChunkRecord`, `SemanticSearchCacheRecord`) is the
   better long-term base, with AFM as reranker on top.
2. **Auto-categorize new clones.** `CategoryClassifier` is heuristic and fast; the AI
   analysis payload already carries `classifications`. Wiring the provider gets
   LLM-quality classification through the existing pipeline; no separate feature needed.
3. **Summarize a repo when shelved.** Chosen. The entire pipeline exists
   (`RepositoryAIAnalyzer` → `AIInsightRecord`/`RepositoryScoreRecord` → InspectView,
   runbooks) but is hard-coded to Ollama, and `.appleIntelligence` is a stub provider
   ("not wired yet", excluded from the picker). Filling the stub completes the app's own
   declared intent with the least new surface area.

## Design

New `AppleIntelligenceService` (Services/AI/) wraps FoundationModels:

- Availability: `SystemLanguageModel.default.availability` mapped to a UI-friendly
  status (available / OS too old / device not eligible / Apple Intelligence off / model
  downloading). Compiled behind `#if canImport(FoundationModels)` +
  `if #available(macOS 26.0, *)` so the macOS 14 deployment target keeps building.
- `generateText(prompt:)` — plain completion for Quick Capture / runbook polish via
  `AICompletionService`.
- `analyzeRepository(prompt:)` — guided generation into a `@Generable` mirror of
  `RepositoryAIAnalysisPayload`. No JSON parsing, no malformed-output failure mode.
  On context-window overflow, the analyzer retries once with trimmed evidence
  (shorter README excerpt, fewer stack/manifest rows).

Integration points:

- `AICompletionService`: both `.appleIntelligence` stub branches call the service.
- `AISettingsSnapshot`: sync + read `reshelf.appleIntelligenceEnabled`;
  `isConfigured` = toggle on AND model actually available.
- `AIProviderKind.selectableProviders`: include Apple Intelligence in the preferred-
  provider picker.
- `RepositoryAIAnalyzer.analyze`: resolves the provider; when Apple Intelligence is
  selected and available, uses guided generation and caches under model name
  `apple-foundation-on-device` (cache keys stay distinct from Ollama analyses).
  Otherwise the Ollama path is unchanged.
- `SettingsView` Apple Intelligence card: live availability status instead of the
  static "Available on macOS 15.2+" line.

Validation: standalone CLI harness (`extras/afm-harness/`) compiled with the Xcode 27
beta toolchain runs the exact analysis prompt + @Generable schema against a real shelf
repo to verify output quality and latency on-device, independent of the app.

## Out of scope

- NL search / embeddings (see above; AFM rerank pattern documented for later).
- AFM-generated embeddings (FoundationModels exposes no embedding API; NLContextualEmbedding
  would be the on-device option).
- Streaming partial generation into the UI.
