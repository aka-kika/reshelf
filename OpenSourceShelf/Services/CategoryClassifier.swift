import Foundation

/// Deterministic classifier that maps GitHub repo info → meaningful category.
/// Categories align with sidebar filters: Database, AI / Agent, macOS, etc.
enum CategoryClassifier {

    /// Classify from GitHub fetch info (used during Quick Capture).
    static func classify(language: String?, topics: [String]?, description: String?, name: String?) -> String {
        let topicSet = Set((topics ?? []).map { $0.lowercased() })
        let desc = (description ?? "").lowercased()
        let repoName = (name ?? "").lowercased()

        // Check topic-based rules first (most reliable signal)
        if let category = classifyFromTopics(topicSet) {
            return category
        }

        // Check description-based rules
        if let category = classifyFromDescription(desc, repoName: repoName) {
            return category
        }

        // Fallback: language-aware heuristics
        if let lang = language {
            return classifyFromLanguage(lang, topics: topicSet, description: desc)
        }

        return ""
    }

    /// Re-classify an existing ToolProject from its stored tags, description, category, and name.
    static func reclassify(tags: [String], description: String, currentCategory: String, name: String, language: String?) -> String {
        // If the current category is already a meaningful one, keep it
        if isMeaningfulCategory(currentCategory) {
            return currentCategory
        }

        // Try classifying from tags (which are often GitHub topics)
        let topicSet = Set(tags.map { $0.lowercased() })
        if let category = classifyFromTopics(topicSet) {
            return category
        }

        // Try from description + name
        let desc = description.lowercased()
        let repoName = name.lowercased()
        if let category = classifyFromDescription(desc, repoName: repoName) {
            return category
        }

        // Try language heuristic
        let lang = language ?? currentCategory  // currentCategory might be a language name
        if !lang.isEmpty {
            return classifyFromLanguage(lang, topics: topicSet, description: desc)
        }

        return currentCategory
    }

    // MARK: - Private

    private static func classifyFromTopics(_ topics: Set<String>) -> String? {
        // Database
        let dbTopics: Set<String> = ["database", "sql", "nosql", "sqlite", "postgresql", "mysql",
                                      "airtable", "spreadsheet", "airtable-alternative", "data-management",
                                      "firebase-alternative", "supabase"]
        if !topics.isDisjoint(with: dbTopics) { return "Database" }

        // AI / Agent
        let aiTopics: Set<String> = ["ai", "llm", "agent", "agents", "machine-learning", "deep-learning",
                                      "chatbot", "langchain", "gpt", "openai", "ollama", "rag",
                                      "artificial-intelligence", "large-language-models", "multiagent-systems",
                                      "agentic-ai", "agentic-workflow", "ai-agent", "ai-agents",
                                      "generative-ai", "text-generation", "inference"]
        if !topics.isDisjoint(with: aiTopics) { return "AI / Agent" }

        // macOS
        let macTopics: Set<String> = ["macos", "macos-app", "mac", "mac-app", "menubar", "menu-bar",
                                       "swift", "swiftui", "cocoa", "appkit", "mac-os-x"]
        if !topics.isDisjoint(with: macTopics) { return "macOS" }

        // Workspace / Productivity
        let workspaceTopics: Set<String> = ["workspace", "notion", "notion-alternative", "wiki",
                                             "collaboration", "project-management", "task-management",
                                             "productivity", "team-collaboration", "kanban"]
        if !topics.isDisjoint(with: workspaceTopics) { return "Workspace" }

        // Internal Tools / Low-Code
        let toolsTopics: Set<String> = ["internal-tools", "low-code", "no-code", "admin-panel",
                                         "dashboard", "admin-dashboard", "retool", "retool-alternative",
                                         "app-builder", "form-builder"]
        if !topics.isDisjoint(with: toolsTopics) { return "Internal Tools" }

        // Backend / API
        let backendTopics: Set<String> = ["backend", "headless-cms", "cms", "api", "rest-api",
                                           "graphql", "baas", "backend-as-a-service"]
        if !topics.isDisjoint(with: backendTopics) { return "Backend" }

        // Knowledge / Docs
        let knowledgeTopics: Set<String> = ["knowledge", "documentation", "note-taking", "notes",
                                             "knowledge-base", "knowledge-management", "markdown",
                                             "second-brain", "pkm", "zettelkasten"]
        if !topics.isDisjoint(with: knowledgeTopics) { return "Knowledge" }

        // CLI / Terminal
        let cliTopics: Set<String> = ["cli", "command-line", "terminal", "tui", "shell"]
        if !topics.isDisjoint(with: cliTopics) { return "CLI" }

        // DevOps / Infrastructure
        let devopsTopics: Set<String> = ["devops", "ci-cd", "docker", "kubernetes", "infrastructure",
                                          "deployment", "monitoring", "observability", "self-hosted"]
        if !topics.isDisjoint(with: devopsTopics) { return "DevOps" }

        // Media / Image / Video
        let mediaTopics: Set<String> = ["media", "video", "image", "image-processing", "gif",
                                         "ffmpeg", "video-editing", "image-editing", "photo",
                                         "screenshot", "screen-recording"]
        if !topics.isDisjoint(with: mediaTopics) { return "Media" }

        // Design
        let designTopics: Set<String> = ["design", "figma", "illustration", "design-system",
                                          "ui-design", "design-tools", "graphics"]
        if !topics.isDisjoint(with: designTopics) { return "Design" }

        // Automation / Workflow
        let automationTopics: Set<String> = ["automation", "workflow", "workflow-automation",
                                              "n8n", "zapier", "pipelines", "etl"]
        if !topics.isDisjoint(with: automationTopics) { return "Automation" }

        // Security
        let securityTopics: Set<String> = ["security", "authentication", "encryption", "auth",
                                            "oauth", "password-manager", "vpn", "privacy"]
        if !topics.isDisjoint(with: securityTopics) { return "Security" }

        // Download / File
        let downloadTopics: Set<String> = ["download", "download-manager", "file-manager",
                                            "file-sharing", "file-transfer", "torrent"]
        if !topics.isDisjoint(with: downloadTopics) { return "Utility" }

        // Editor / IDE
        let editorTopics: Set<String> = ["editor", "text-editor", "code-editor", "ide",
                                          "markdown-editor", "rich-text-editor"]
        if !topics.isDisjoint(with: editorTopics) { return "Editor" }

        return nil
    }

    private static func classifyFromDescription(_ desc: String, repoName: String) -> String? {
        // Database signals
        if desc.contains("database") || desc.contains("airtable alternative") || desc.contains("spreadsheet") {
            return "Database"
        }

        // AI signals
        if desc.contains("ai agent") || desc.contains("llm") || desc.contains("language model")
            || desc.contains("chatbot") || desc.contains("machine learning") {
            return "AI / Agent"
        }

        // macOS signals
        if desc.contains("macos") || desc.contains("mac app") || desc.contains("menu bar")
            || desc.contains("for mac") || desc.contains("native macos") {
            return "macOS"
        }

        // Workspace
        if desc.contains("notion alternative") || desc.contains("project management")
            || desc.contains("collaboration") || desc.contains("workspace") {
            return "Workspace"
        }

        // Internal tools
        if desc.contains("internal tool") || desc.contains("low-code") || desc.contains("no-code")
            || desc.contains("admin panel") || desc.contains("app builder") {
            return "Internal Tools"
        }

        // Download manager
        if desc.contains("download manager") || desc.contains("download accelerator") {
            return "Utility"
        }

        // Image processing
        if desc.contains("image") && (desc.contains("processing") || desc.contains("editing") || desc.contains("conversion")) {
            return "Media"
        }

        // Editor
        if desc.contains("text editor") || desc.contains("markdown editor") || desc.contains("code editor") {
            return "Editor"
        }

        // Input source / keyboard
        if desc.contains("input source") || desc.contains("keyboard") || desc.contains("clipboard") {
            return "Utility"
        }

        return nil
    }

    private static func classifyFromLanguage(_ language: String, topics: Set<String>, description: String) -> String {
        let lang = language.lowercased()

        // Swift projects on macOS are likely macOS tools
        if lang == "swift" || lang == "objective-c" {
            if description.contains("macos") || description.contains("mac ") || description.contains("for mac")
                || topics.contains("macos") || topics.contains("swiftui") || topics.contains("appkit") {
                return "macOS"
            }
            // Default for Swift is still macOS since this is a macOS app catalog
            return "macOS"
        }

        // Python with AI-related description
        if lang == "python" {
            if description.contains("ai") || description.contains("agent") || description.contains("llm")
                || description.contains("machine learning") || description.contains("model") {
                return "AI / Agent"
            }
        }

        // Return the language as fallback (still better than empty)
        return language
    }

    /// Check if a category is a meaningful classification vs just a language name.
    static func isMeaningfulCategory(_ category: String) -> Bool {
        let meaningful: Set<String> = [
            "Database", "AI / Agent", "macOS", "Workspace", "Internal Tools",
            "Backend", "Knowledge", "CLI", "DevOps", "Media", "Design",
            "Automation", "Security", "Utility", "Editor"
        ]
        return meaningful.contains(category)
    }
}
