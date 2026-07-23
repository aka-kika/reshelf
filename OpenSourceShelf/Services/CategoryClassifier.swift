import Foundation

/// Deterministic classifier that maps GitHub repo info → meaningful category.
/// Categories align with sidebar filters: Database, AI / Agent, macOS, etc.
///
/// Precision strategy: every category collects a weighted score from topics,
/// description, and repo name — word-boundary matched, never raw substrings
/// (so "storage" can't hit "rag", "maintain" can't hit "ai") — and the highest
/// score wins. Strong signals ("airtable-alternative", "menubar") outweigh
/// broad ones ("api", "dashboard"), instead of whichever rule was checked first.
enum CategoryClassifier {

    /// Classify from GitHub fetch info (used during Quick Capture).
    static func classify(language: String?, topics: [String]?, description: String?, name: String?) -> String {
        if let category = scoredCategory(topics: topics ?? [], description: description ?? "", name: name ?? "") {
            return category
        }
        if let lang = language {
            return classifyFromLanguage(lang, description: (description ?? "").lowercased())
        }
        return ""
    }

    /// Re-classify an existing ToolProject from its stored tags, description, category, and name.
    /// Any existing non-empty category that isn't a leaked raw language name is kept
    /// — whether the classifier produced it or the user sorted it by hand — because
    /// the two are indistinguishable. Only empty/language rows are (re)scored.
    static func reclassify(tags: [String], description: String, currentCategory: String, name: String, language: String?, force: Bool = false) -> String {
        let current = currentCategory.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty, !isLanguageName(current) {
            return currentCategory
        }
        if let category = scoredCategory(topics: tags, description: description, name: name) {
            return category
        }
        // Try language heuristic (currentCategory might be a raw language name)
        let lang = language ?? current
        let fromLanguage = lang.isEmpty ? "" : classifyFromLanguage(lang, description: description.lowercased())
        if !fromLanguage.isEmpty {
            return fromLanguage
        }
        // No signal at all: keep a meaningful category (force mode found nothing
        // better), but still blank a raw language name rather than keep it.
        return isLanguageName(current) ? "" : currentCategory
    }

    /// Check if a category is one the classifier itself produces.
    static func isMeaningfulCategory(_ category: String) -> Bool {
        let meaningful: Set<String> = [
            "Database", "MCP", "AI / Agent", "Coding Agents", "Computer Use", "AI Memory",
            "macOS", "SwiftUI", "Workspace", "Internal Tools",
            "Backend", "Knowledge", "CLI", "DevOps", "Media", "Design",
            "Automation", "Security", "Utility", "Editor", "Frontend", "Games"
        ]
        return meaningful.contains(category)
    }

    /// Raw language names that older captures leaked into the category field —
    /// besides empty values, the ONLY stored categories reclassification may
    /// overwrite without `force`. Anything else a user typed is theirs to keep.
    private static let languageNames: Set<String> = [
        "swift", "objective-c", "objective c", "python", "typescript", "javascript",
        "go", "golang", "rust", "c", "c++", "c#", "java", "kotlin", "ruby", "php",
        "shell", "bash", "zsh", "html", "css", "scss", "lua", "zig", "dart",
        "elixir", "haskell", "scala", "perl", "r", "vue", "svelte",
        "jupyter notebook", "makefile", "dockerfile", "cmake", "assembly",
        "clojure", "ocaml", "nim", "crystal"
    ]

    static func isLanguageName(_ category: String) -> Bool {
        languageNames.contains(category.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Whether the launch pass may touch this stored category at all: ONLY empty
    /// and raw-language values. A stored meaningful category may be the user's own
    /// manual sorting — indistinguishable from classifier output — so classifier
    /// upgrades never overwrite it, `force` or not. (Learned the hard way: a force
    /// re-score once flattened dozens of hand-sorted Coding Agents / Computer Use /
    /// AI Memory rows into AI / Agent.) Rule improvements apply to new captures and
    /// to still-uncategorized rows; existing assignments are corrected by hand.
    static func shouldReclassify(_ category: String, force: Bool) -> Bool {
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || isLanguageName(trimmed)
    }

    // MARK: - Scoring

    private struct Rule {
        let category: String
        /// Topics that on their own identify the category (matched against whole
        /// topics and their hyphen-split tokens).
        let strongTopics: Set<String>
        /// Broad topics that only hint at the category.
        let weakTopics: Set<String>
        /// Description phrases that identify the category (word-boundary matched,
        /// pre-normalized: lowercase, alphanumerics + single spaces).
        let strongPhrases: [String]
        /// Broad description words — one alone is never enough to classify.
        let weakPhrases: [String]
    }

    private static let strongTopicWeight = 4
    private static let weakTopicWeight = 2
    private static let strongPhraseWeight = 3
    private static let weakPhraseWeight = 1
    private static let nameTokenWeight = 2
    /// Minimum winning score: a single broad description word (weight 1) stays
    /// uncategorized; a single topic or strong phrase is enough.
    private static let minimumScore = 2

    /// Rules in tie-break order (earlier wins on equal score) — mirrors the old
    /// first-match priority so existing shelves don't reshuffle on ties.
    private static let rules: [Rule] = [
        Rule(category: "Database",
             strongTopics: ["database", "sqlite", "postgresql", "postgres", "mysql", "nosql",
                            "airtable", "airtable-alternative", "supabase", "firebase-alternative",
                            "duckdb", "redis", "mongodb", "clickhouse", "vector-database", "orm",
                            "spreadsheet", "data-management"],
             weakTopics: ["sql"],
             strongPhrases: ["database", "airtable alternative", "vector database", "sql engine"],
             weakPhrases: ["sql"]),

        Rule(category: "MCP",
             strongTopics: ["mcp", "model-context-protocol", "mcp-server", "mcp-servers",
                            "mcp-client", "mcp-clients", "mcp-tools"],
             weakTopics: [],
             strongPhrases: ["model context protocol", "mcp server", "mcp client", "mcp"],
             weakPhrases: []),

        Rule(category: "Coding Agents",
             strongTopics: ["coding-agent", "code-agent", "ai-coding", "code-generation",
                            "codegen", "pair-programming", "code-assistant", "ai-pair-programmer",
                            "swe-agent", "agentic-coding"],
             weakTopics: ["copilot"],
             strongPhrases: ["coding agent", "code agent", "coding assistant", "ai coding",
                             "autonomous coding", "ai pair programmer", "software engineering agent",
                             "agentic coding", "code editor for the ai"],
             weakPhrases: []),

        Rule(category: "Computer Use",
             strongTopics: ["computer-use", "computer-using-agent", "gui-agent", "browser-use",
                            "browser-automation", "desktop-automation", "rpa", "web-automation",
                            "ui-automation"],
             weakTopics: [],
             strongPhrases: ["computer use", "computer using agent", "control the computer",
                             "control your computer", "browser automation", "gui agent",
                             "screen mouse and keyboard", "desktop automation"],
             weakPhrases: []),

        Rule(category: "AI Memory",
             strongTopics: ["memory", "rag", "long-term-memory", "context-management",
                            "context-engineering", "retrieval-augmented-generation",
                            "vector-memory", "semantic-memory"],
             weakTopics: ["retrieval"],
             strongPhrases: ["memory layer", "memory engine", "ai memory", "memory for ai",
                             "context management", "long term memory", "retrieval augmented",
                             "persistent memory"],
             weakPhrases: ["rag"]),

        Rule(category: "AI / Agent",
             strongTopics: ["ai", "llm", "llms", "agent", "agents", "ai-agent", "chatgpt", "gpt",
                            "ollama", "langchain",
                            "llamaindex", "chatbot", "machine-learning",
                            "deep-learning", "artificial-intelligence", "generative-ai",
                            "transformers", "embeddings", "mlx", "whisper", "stable-diffusion",
                            "prompt-engineering", "genai"],
             // Provider names are weak on purpose: a terminal or editor tagged
             // "claude"/"gemini" usually just integrates AI, it isn't an AI tool.
             weakTopics: ["inference", "neural-network", "openai", "anthropic", "claude", "gemini"],
             strongPhrases: ["ai agent", "ai assistant", "autonomous agent",
                             "language model", "llm", "machine learning", "deep learning",
                             "chatbot", "ai powered", "generative ai", "ai coworker",
                             "speech to text"],
             weakPhrases: ["ai", "agent", "dictation", "transcription"]),

        // Before macOS in tie-break order: a repo whose identity IS SwiftUI (a
        // component/animation library, a SwiftUI example collection) should land
        // in SwiftUI. A mac APP that merely uses SwiftUI still wins macOS,
        // because its macos/menubar signals outscore the lone swiftui topic.
        Rule(category: "SwiftUI",
             strongTopics: ["swiftui", "swift-ui", "swiftui-components", "swiftui-library",
                            "swiftui-animations", "swiftui-example", "swiftui-tutorial",
                            "swiftui-framework"],
             weakTopics: [],
             strongPhrases: ["swiftui", "swift ui", "swiftui library", "for swiftui",
                             "swiftui component", "swiftui components", "swiftui view"],
             // Library-shape words: alone they can never classify (weight 1 <
             // minimum 2) — they only tip a swiftui-tagged LIBRARY over the
             // platform topics (macos/ios) that cross-platform packages carry,
             // while apps ("menu bar app built with SwiftUI") still win macOS.
             weakPhrases: ["library", "framework", "components", "renderer", "package"]),

        Rule(category: "macOS",
             strongTopics: ["macos", "macos-app", "mac-app", "menubar", "menu-bar", "menubar-app",
                            "appkit", "cocoa", "mac-os-x", "osx"],
             weakTopics: ["swift", "mac", "apple", "swiftui"],
             strongPhrases: ["macos", "mac app", "menu bar", "for mac", "native macos",
                             "status bar app"],
             weakPhrases: ["mac"]),

        Rule(category: "Workspace",
             strongTopics: ["workspace", "notion", "notion-alternative", "wiki",
                            "project-management", "task-management", "team-collaboration",
                            "kanban", "todo-list", "calendar", "anytype", "affine", "appflowy",
                            "trello", "trello-alternative"],
             weakTopics: ["collaboration", "productivity", "todo"],
             strongPhrases: ["notion alternative", "project management", "task management",
                             "kanban", "trello alternative", "task tracker", "office suite"],
             weakPhrases: ["collaboration", "workspace", "productivity", "todo", "tasks"]),

        Rule(category: "Internal Tools",
             strongTopics: ["internal-tools", "low-code", "no-code", "admin-panel",
                            "admin-dashboard", "retool", "retool-alternative", "app-builder",
                            "form-builder"],
             weakTopics: ["dashboard"],
             strongPhrases: ["internal tool", "internal tools", "low code", "no code",
                             "admin panel", "app builder", "form builder"],
             weakPhrases: ["dashboard"]),

        Rule(category: "Backend",
             strongTopics: ["backend", "headless-cms", "cms", "baas", "backend-as-a-service",
                            "rest-api", "graphql", "web-framework"],
             weakTopics: ["api", "server", "framework"],
             strongPhrases: ["headless cms", "backend as a service", "rest api", "graphql api",
                             "web framework"],
             weakPhrases: ["backend", "api", "server"]),

        Rule(category: "Knowledge",
             strongTopics: ["note-taking", "notes", "knowledge-base", "knowledge-management",
                            "second-brain", "pkm", "zettelkasten", "obsidian", "documentation",
                            "logseq", "joplin", "trilium", "notebook", "memos",
                            "journal", "journaling"],
             weakTopics: ["markdown", "knowledge", "writing"],
             strongPhrases: ["note taking", "knowledge base", "knowledge bases",
                             "knowledge management", "second brain", "personal knowledge",
                             "note tool", "notes app", "journaling", "journal app"],
             weakPhrases: ["notes", "note", "markdown", "documentation", "wiki", "journal"]),

        Rule(category: "CLI",
             strongTopics: ["cli", "command-line", "command-line-tool", "tui", "terminal"],
             weakTopics: ["shell", "zsh", "bash"],
             strongPhrases: ["command line", "cli", "terminal ui", "terminal app", "tui",
                             "terminal emulator"],
             weakPhrases: ["terminal", "shell"]),

        Rule(category: "DevOps",
             strongTopics: ["devops", "ci-cd", "kubernetes", "docker", "infrastructure",
                            "observability", "monitoring", "deployment", "terraform", "helm",
                            "ansible", "containers"],
             weakTopics: ["self-hosted"],
             strongPhrases: ["continuous integration", "ci cd", "kubernetes", "observability",
                             "infrastructure as code", "monitoring"],
             weakPhrases: ["deploy", "docker", "self hosted", "devops"]),

        Rule(category: "Media",
             strongTopics: ["ffmpeg", "video-editing", "image-editing", "image-processing",
                            "screen-recording", "screenshot", "gif", "photo"],
             weakTopics: ["video", "image", "audio", "music", "camera"],
             strongPhrases: ["video editing", "video editor", "image processing", "image editing",
                             "screen recording", "screenshot", "media player"],
             weakPhrases: ["video", "image", "audio", "music", "media", "photo"]),

        Rule(category: "Design",
             strongTopics: ["figma", "design-system", "ui-design", "design-tools", "illustration",
                            "design", "icons", "typography", "css", "tailwind", "tailwindcss"],
             weakTopics: ["graphics", "fonts", "ui"],
             strongPhrases: ["design system", "ui design", "design tool", "vector graphics",
                             "css framework", "styling system"],
             weakPhrases: ["design", "illustration", "icons"]),

        Rule(category: "Automation",
             strongTopics: ["automation", "workflow-automation", "n8n", "zapier", "etl",
                            "web-scraping", "scraper", "web-crawler", "social-media"],
             weakTopics: ["workflow", "pipelines", "cron", "scheduler"],
             strongPhrases: ["workflow automation", "automation", "web scraping", "web scraper",
                             "social media scheduling"],
             weakPhrases: ["workflow", "pipeline", "scheduler"]),

        Rule(category: "Security",
             strongTopics: ["security", "password-manager", "encryption", "authentication",
                            "oauth", "vpn", "2fa", "secrets-management", "auth"],
             weakTopics: ["privacy", "passwords", "firewall"],
             strongPhrases: ["password manager", "encryption", "authentication", "two factor",
                             "end to end encrypted"],
             weakPhrases: ["security", "privacy", "vpn", "encrypted"]),

        Rule(category: "Utility",
             strongTopics: ["download-manager", "file-manager", "file-sharing", "file-transfer",
                            "torrent", "clipboard-manager", "launcher", "window-manager",
                            "hotkey", "uninstaller"],
             weakTopics: ["utility", "files"],
             strongPhrases: ["download manager", "file manager", "clipboard manager",
                             "window management", "app launcher", "download accelerator",
                             "file management"],
             weakPhrases: ["clipboard", "keyboard", "input source", "file transfer", "launcher"]),

        Rule(category: "Editor",
             strongTopics: ["editor", "text-editor", "code-editor", "markdown-editor",
                            "rich-text-editor", "ide", "vim", "neovim", "wysiwyg"],
             weakTopics: [],
             strongPhrases: ["text editor", "code editor", "markdown editor", "rich text editor"],
             weakPhrases: ["editor", "ide"]),

        // Last in tie-break order on purpose: web libraries often carry broad
        // topics (ui, javascript) that shouldn't outrank the categories above.
        // Framework names are weak: apps are routinely topic-tagged with their
        // stack ("react", "nextjs") without BEING frontend libraries.
        Rule(category: "Frontend",
             strongTopics: ["frontend", "component-library", "ui-components",
                            "web-components"],
             weakTopics: ["react", "reactjs", "vuejs", "nextjs", "javascript",
                          "typescript", "web"],
             strongPhrases: ["frontend", "component library", "ui library",
                             "animation library", "react component"],
             weakPhrases: ["react", "web app"]),

        Rule(category: "Games",
             strongTopics: ["game-engine", "game-development", "gamedev", "game", "games",
                            "godot", "unity"],
             weakTopics: [],
             strongPhrases: ["game engine", "game development", "2d and 3d game"],
             weakPhrases: ["game"]),
    ]

    /// Highest-scoring category across all rules, or nil when nothing clears the
    /// minimum score (better to leave a repo uncategorized than to guess).
    private static func scoredCategory(topics: [String], description: String, name: String) -> String? {
        // Each topic both as a whole ("note-taking") and as its tokens ("note",
        // "taking") so compound topics match without substring false positives.
        var topicTerms = Set<String>()
        for topic in topics {
            let lowered = topic.lowercased()
            topicTerms.insert(lowered)
            topicTerms.formUnion(tokens(of: lowered))
        }
        let nameTokens = Set(tokens(of: name.lowercased()))
        let descWords = normalizedWords(description)

        var best: (category: String, score: Int)?
        for rule in rules {
            var score = 0
            score += rule.strongTopics.intersection(topicTerms).count * strongTopicWeight
            score += rule.weakTopics.intersection(topicTerms).count * weakTopicWeight
            score += rule.strongTopics.intersection(nameTokens).count * nameTokenWeight
            for phrase in rule.strongPhrases where descWords.contains(" \(phrase) ") {
                score += strongPhraseWeight
            }
            for phrase in rule.weakPhrases where descWords.contains(" \(phrase) ") {
                score += weakPhraseWeight
            }
            if score >= minimumScore, score > (best?.score ?? 0) {
                best = (rule.category, score)
            }
        }
        return best?.category
    }

    /// Lowercased text reduced to alphanumeric words separated (and surrounded)
    /// by single spaces, so ` phrase ` containment is a word-boundary match.
    private static func normalizedWords(_ text: String) -> String {
        let mapped = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        let collapsed = String(mapped).split(separator: " ").joined(separator: " ")
        return " \(collapsed) "
    }

    /// Alphanumeric tokens of a topic or repo name ("ai-agent" → ["ai", "agent"]).
    private static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func classifyFromLanguage(_ language: String, description: String) -> String {
        let lang = language.lowercased()

        // Swift projects are likely macOS tools in a macOS app catalog.
        if lang == "swift" || lang == "objective-c" {
            return "macOS"
        }

        // Python with AI-ish wording (word-boundary — "ai" must not hit "maintain").
        if lang == "python" {
            let words = normalizedWords(description)
            for hint in ["ai", "agent", "llm", "machine learning", "model"]
            where words.contains(" \(hint) ") {
                return "AI / Agent"
            }
        }

        // No meaningful signal: stay uncategorized rather than leaking a raw
        // language name ("TypeScript", "Go") as a fake category — languages
        // aren't browsable categories and orphan the repo from the sidebar.
        return ""
    }
}
