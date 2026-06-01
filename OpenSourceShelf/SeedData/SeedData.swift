import SwiftData
import Foundation

enum SeedData {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ToolProject>()
        guard let count = try? context.fetch(descriptor).count, count == 0 else { return }

        let projects: [ToolProject] = [
            ToolProject(
                name: "Baserow",
                shortDescription: "Open-source no-code database tool",
                longDescription: "Baserow is an open-source no-code database tool and Airtable alternative. It lets you organize data in rows and columns and build applications on top of it.",
                githubURL: "https://github.com/bramw/baserow",
                websiteURL: "https://baserow.io",
                category: "Database",
                status: .topShelf,
                license: "AGPL-3.0",
                stars: "18.2k",
                tags: ["database", "no-code", "self-hosted", "airtable-alternative"],
                useCases: [
                    "Build internal tools and admin panels",
                    "Create custom databases and interfaces",
                    "Prototype data models and workflows",
                    "Replace spreadsheets and Airtable"
                ],
                notes: "Great for quickly setting up a database structure. Good reference for database UX and permissions.",
                fitScore: 4,
                isLocalFirst: true,
                isSelfHosted: true
            ),
            ToolProject(
                name: "NocoDB",
                shortDescription: "Airtable alternative for any SQL database",
                longDescription: "NocoDB is an open-source platform that turns any database into a smart spreadsheet. It connects to MySQL, PostgreSQL, SQL Server, SQLite, and more.",
                githubURL: "https://github.com/nocodb/nocodb",
                websiteURL: "https://nocodb.com",
                category: "Database",
                status: .collector,
                license: "AGPL-3.0",
                stars: "56.1k",
                tags: ["database", "sql", "airtable-alternative"],
                useCases: [
                    "Front-end for existing SQL databases",
                    "Collaborative spreadsheets with teams",
                    "Quick CRUD interfaces"
                ],
                notes: "Massive community. Good alternative to Baserow with broader SQL support.",
                fitScore: 4,
                isSelfHosted: true
            ),
            ToolProject(
                name: "AppFlowy",
                shortDescription: "Open-source Notion alternative",
                longDescription: "AppFlowy is an open-source workspace for notes, tasks, databases, and wikis. It's built with Flutter and Rust and emphasizes data privacy and local-first principles.",
                githubURL: "https://github.com/AppFlowy-IO/appflowy",
                websiteURL: "https://appflowy.io",
                category: "Workspace",
                status: .topShelf,
                license: "AGPL-3.0",
                stars: "64.2k",
                tags: ["notes", "workspace", "local-first"],
                useCases: [
                    "Personal knowledge management",
                    "Project documentation",
                    "Task tracking and databases"
                ],
                notes: "Clean Notion alternative. Great for personal use. The Flutter + Rust stack is interesting.",
                fitScore: 3,
                isLocalFirst: true
            ),
            ToolProject(
                name: "Budibase",
                shortDescription: "Open-source low-code platform",
                longDescription: "Budibase is an open-source low-code platform for building internal tools, admin panels, and business apps quickly.",
                githubURL: "https://github.com/Budibase/budibase",
                websiteURL: "https://budibase.com",
                category: "Internal Tools",
                status: .collector,
                license: "GPL-3.0",
                stars: "24.5k",
                tags: ["internal-tools", "database", "app-builder"],
                useCases: [
                    "Build internal business tools",
                    "Create admin panels for databases",
                    "Automate business workflows"
                ],
                notes: "Strong focus on internal tools. Good UI builder.",
                fitScore: 3,
                isSelfHosted: true
            ),
            ToolProject(
                name: "ToolJet",
                shortDescription: "Open-source internal tool builder",
                longDescription: "ToolJet is an open-source low-code platform to build and deploy internal tools, dashboards, and admin panels.",
                githubURL: "https://github.com/ToolJet/ToolJet",
                websiteURL: "https://tooljet.com",
                category: "Internal Tools",
                status: .collector,
                license: "AGPL-3.0",
                stars: "36.8k",
                tags: ["internal-tools", "dashboard", "workflow"],
                useCases: [
                    "Build internal dashboards",
                    "Connect multiple data sources",
                    "Create automated workflows"
                ],
                notes: "Very popular for internal dashboards. Worth evaluating.",
                fitScore: 3,
                isSelfHosted: true
            ),
            ToolProject(
                name: "Directus",
                shortDescription: "Open-source headless CMS",
                longDescription: "Directus is an open-source headless CMS that wraps any SQL database with a dynamic API and no-code admin app.",
                githubURL: "https://github.com/directus/directus",
                websiteURL: "https://directus.io",
                category: "Backend",
                status: .collector,
                license: "BUSL-1.1",
                stars: "30.1k",
                tags: ["backend", "cms", "database"],
                useCases: [
                    "Headless CMS for any database",
                    "API layer for existing databases",
                    "Content management for apps and websites"
                ],
                notes: "Excellent for API-first projects. Works with existing databases without migration.",
                fitScore: 3,
                isSelfHosted: true
            ),
            ToolProject(
                name: "Outline",
                shortDescription: "Knowledge base and wiki",
                longDescription: "Outline is an open-source knowledge base and wiki built with React and Node.js. It features fast search, markdown editing, and real-time collaboration.",
                githubURL: "https://github.com/outline/outline",
                websiteURL: "https://getoutline.com",
                category: "Knowledge",
                status: .topShelf,
                license: "BUSL-1.1",
                stars: "31.4k",
                tags: ["docs", "knowledge-base", "wiki"],
                useCases: [
                    "Internal team documentation",
                    "Personal knowledge base",
                    "Project wikis and guides"
                ],
                notes: "Beautiful UI, excellent search. Great for documentation-heavy workflows.",
                fitScore: 4,
                isSelfHosted: true
            ),
            ToolProject(
                name: "FlowiseAI",
                shortDescription: "Build LLM apps visually",
                longDescription: "Flowise is an open-source visual builder for LLM applications. Drag and drop components to build AI workflows, chains, and agents.",
                githubURL: "https://github.com/FlowiseAI/Flowise",
                websiteURL: "https://flowiseai.com",
                category: "AI / Agent",
                status: .collector,
                license: "Apache-2.0",
                stars: "41.7k",
                tags: ["ai", "agent", "llm", "workflow"],
                useCases: [
                    "Build RAG chatbots",
                    "Create AI agent workflows",
                    "Prototype LLM applications",
                    "Connect LLMs to external tools"
                ],
                notes: "Leading visual AI builder. Worth exploring for agent and chatbot workflows.",
                fitScore: 4
            )
        ]

        for project in projects {
            context.insert(project)
        }
        try? context.save()
    }
}
