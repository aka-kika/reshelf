import SwiftData
import Foundation

/// The nine projects a fresh install starts with.
///
/// Fill-only: runs solely when the catalog is genuinely empty, so it can never
/// overwrite a real shelf. `CatalogBackupService.restoreIfCatalogEmpty` gets first
/// refusal — if a backup exists, that is restored and this never runs.
///
/// The mix is deliberate. Every sidebar category that matters shows at least one
/// row on first launch (AI, macOS, MCP, CLI, Design, Editor, Media), the licences
/// are real and verified at the time of writing, and nothing here is obscure
/// enough to feel like someone else's bookmarks. `immich` is AGPL on purpose:
/// it means the copyleft caution demonstrates itself on day one instead of
/// waiting for the user to stumble into it.
///
/// Star counts go stale — that's expected and harmless. They refresh the first
/// time a repo's metadata is fetched.
enum SeedData {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ToolProject>()
        guard let count = try? context.fetch(descriptor).count, count == 0 else { return }

        let projects: [ToolProject] = [
            ToolProject(
                name: "jade",
                shortDescription: "Native macOS terminal workspace built on libghostty",
                longDescription: "Jade is a native macOS terminal workspace: project tabs, splits, a command palette, Ollama AI, and Obsidian capture. Built with SwiftUI on libghostty.",
                githubURL: "https://github.com/aka-kika/jade",
                websiteURL: "https://aka-kika.github.io/jade/",
                category: "macOS",
                status: .topShelf,
                license: "MIT",
                stars: "1",
                tags: ["terminal", "macos", "swiftui", "libghostty"],
                useCases: [
                    "Keep each project's terminals in their own tab",
                    "Drive a terminal from a command palette",
                    "Capture terminal output into Obsidian"
                ],
                notes: "Built on libghostty — the same engine as ghostty, further down this list.",
                fitScore: 4,
                isLocalFirst: true
            ),
            ToolProject(
                name: "Seedling",
                shortDescription: "A tiny, calm macOS app for starting new projects",
                longDescription: "🌱 Plant a seed and watch it grow — a tiny, calm macOS app for starting new projects. Made for late nights and fresh beginnings.",
                githubURL: "https://github.com/aka-kika/Seedling",
                websiteURL: "",
                category: "macOS",
                status: .collector,
                license: "MIT",
                stars: "2",
                tags: ["macos", "swiftui", "productivity", "menu-bar"],
                useCases: [
                    "Start a new project without ceremony",
                    "Keep a small idea somewhere calm"
                ],
                notes: "Small on purpose. A good read if you want to see how little a macOS app can be.",
                fitScore: 4,
                isLocalFirst: true
            ),
            ToolProject(
                name: "kika-obsidian-mcp",
                shortDescription: "Local-first MCP server for Obsidian vaults",
                longDescription: "Local-first MCP server for Obsidian vaults — no plugins, no API keys, with schema-validated Bases (.base) support.",
                githubURL: "https://github.com/aka-kika/kika-obsidian-mcp",
                websiteURL: "https://akakika.com/blog/obsidian-codex-mcp-landing.html",
                category: "MCP",
                status: .topShelf,
                license: "MIT",
                stars: "8",
                tags: ["mcp", "obsidian", "local-first", "agents"],
                useCases: [
                    "Let an agent read and write an Obsidian vault",
                    "Query notes without a plugin or API key",
                    "Validate Obsidian Bases against a schema"
                ],
                notes: "No plugins and no keys — the vault stays a folder of Markdown.",
                fitScore: 5,
                isLocalFirst: true
            ),
            ToolProject(
                name: "ollama",
                shortDescription: "Run local language models with one command",
                longDescription: "Get up and running with local language models — Kimi, GLM, MiniMax, DeepSeek, gpt-oss, Qwen, Gemma and others.",
                githubURL: "https://github.com/ollama/ollama",
                websiteURL: "https://ollama.com",
                category: "AI / Agent",
                status: .topShelf,
                license: "MIT",
                stars: "177k",
                tags: ["ai", "llm", "local-first", "cli"],
                useCases: [
                    "Run a language model entirely on your own machine",
                    "Serve a local model to other tools over HTTP",
                    "Try a new model without an API key"
                ],
                notes: "The front door to local LLMs. Most local-AI tools speak to it.",
                fitScore: 5,
                isLocalFirst: true
            ),
            ToolProject(
                name: "Handy",
                shortDescription: "Offline speech-to-text for your Mac",
                longDescription: "A free, open source, and extensible speech-to-text application that works completely offline.",
                githubURL: "https://github.com/cjpais/handy",
                websiteURL: "https://handy.computer",
                category: "AI / Agent",
                status: .collector,
                license: "MIT",
                stars: "27.7k",
                tags: ["ai", "speech-to-text", "local-first", "offline"],
                useCases: [
                    "Dictate without sending audio anywhere",
                    "Transcribe recordings on your own machine"
                ],
                notes: "AI that genuinely runs on your machine — nothing to sign up for.",
                fitScore: 4,
                isLocalFirst: true
            ),
            ToolProject(
                name: "zed",
                shortDescription: "High-performance multiplayer code editor",
                longDescription: "Code at the speed of thought — Zed is a high-performance, multiplayer code editor from the creators of Atom and Tree-sitter.",
                githubURL: "https://github.com/zed-industries/zed",
                websiteURL: "https://zed.dev",
                category: "Editor",
                status: .topShelf,
                license: "GPL-3.0",
                stars: "87.6k",
                tags: ["editor", "rust", "collaboration"],
                useCases: [
                    "Edit code with very low input latency",
                    "Pair on a file with someone else live",
                    "Read a large real-world Rust codebase"
                ],
                notes: "Dual-licensed — GPL for the editor, Apache for parts of the tree.",
                fitScore: 4
            ),
            ToolProject(
                name: "excalidraw",
                shortDescription: "Virtual whiteboard with a hand-drawn look",
                longDescription: "Virtual whiteboard for sketching hand-drawn like diagrams. Collaborative, end-to-end encrypted, and works offline.",
                githubURL: "https://github.com/excalidraw/excalidraw",
                websiteURL: "https://excalidraw.com",
                category: "Design",
                status: .topShelf,
                license: "MIT",
                stars: "128.5k",
                tags: ["design", "whiteboard", "diagrams", "canvas"],
                useCases: [
                    "Sketch an architecture diagram quickly",
                    "Draw something rough without it looking corporate",
                    "Embed a diagram in docs"
                ],
                notes: "Permissive and easy to embed. Pleasant to read as a canvas implementation.",
                fitScore: 4
            ),
            ToolProject(
                name: "lazygit",
                shortDescription: "Terminal UI for git",
                longDescription: "A simple terminal UI for git commands — stage hunks, rebase interactively, and resolve conflicts without leaving the terminal.",
                githubURL: "https://github.com/jesseduffield/lazygit",
                websiteURL: "",
                category: "CLI",
                status: .collector,
                license: "MIT",
                stars: "80.8k",
                tags: ["cli", "git", "tui", "terminal"],
                useCases: [
                    "Stage individual hunks without memorising flags",
                    "Do an interactive rebase you can actually see",
                    "Resolve merge conflicts in the terminal"
                ],
                notes: "The one git tool most terminal people keep.",
                fitScore: 5
            ),
            ToolProject(
                name: "immich",
                shortDescription: "Self-hosted photo and video library",
                longDescription: "High performance self-hosted photo and video management solution — a private alternative to cloud photo libraries.",
                githubURL: "https://github.com/immich-app/immich",
                websiteURL: "https://immich.app",
                category: "Media",
                status: .collector,
                license: "AGPL-3.0",
                stars: "109k",
                tags: ["media", "photos", "self-hosted", "local-first"],
                useCases: [
                    "Host your own photo library",
                    "Back up phone photos to hardware you own",
                    "Search photos without a cloud account"
                ],
                notes: "AGPL — fine to run and study, but read the licence before reusing its code.",
                fitScore: 4,
                isSelfHosted: true
            )
        ]

        for project in projects {
            context.insert(project)
        }
        try? context.save()
    }
}
