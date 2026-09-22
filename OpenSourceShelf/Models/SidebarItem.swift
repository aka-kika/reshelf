import SwiftUI

enum SidebarItem: String, Identifiable, CaseIterable {
    // Library (shelf state)
    case allProjects = "allProjects"
    case topShelf = "topShelf"
    case collector = "collector"
    case yardSale = "yardSale"
    case cloned = "cloned"

    // Categories
    case databaseTools = "databaseTools"
    case backendTools = "backendTools"
    case agentTools = "agentTools"
    case codingAgentTools = "codingAgentTools"
    case computerUseTools = "computerUseTools"
    case aiMemoryTools = "aiMemoryTools"
    case mcpTools = "mcpTools"
    case internalTools = "internalTools"
    case workspaceTools = "workspaceTools"
    case knowledgeTools = "knowledgeTools"
    case macOSTools = "macOSTools"
    case swiftUITools = "swiftUITools"
    case cliTools = "cliTools"
    case editorTools = "editorTools"
    case devopsTools = "devopsTools"
    case automationTools = "automationTools"
    case mediaTools = "mediaTools"
    case designTools = "designTools"
    case securityTools = "securityTools"
    case utilityTools = "utilityTools"
    case frontendTools = "frontendTools"
    case gamesTools = "gamesTools"
    case localFirst = "localFirst"

    // Intelligence (v2 — Labs) destinations

    // Settings
    case settings = "settings"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allProjects: "All Projects"
        case .topShelf: "Top Shelf"
        case .collector: "The Collector"
        case .yardSale: "Yard Sale"
        case .cloned: "Cloned"
        case .databaseTools: "Database"
        case .backendTools: "Backend"
        case .agentTools: "AI / Agent"
        case .codingAgentTools: "Coding Agents"
        case .computerUseTools: "Computer Use"
        case .aiMemoryTools: "AI Memory"
        case .mcpTools: "MCP"
        case .internalTools: "Internal Tools"
        case .workspaceTools: "Workspace"
        case .knowledgeTools: "Knowledge"
        case .macOSTools: "macOS"
        case .swiftUITools: "SwiftUI"
        case .cliTools: "CLI"
        case .editorTools: "Editor"
        case .devopsTools: "DevOps"
        case .automationTools: "Automation"
        case .mediaTools: "Media"
        case .designTools: "Design"
        case .securityTools: "Security"
        case .utilityTools: "Utility"
        case .frontendTools: "Frontend"
        case .gamesTools: "Games"
        case .localFirst: "Local-First"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .allProjects: "square.grid.2x2"
        case .topShelf: "star.fill"
        case .collector: "square.stack.3d.up"
        case .yardSale: "tag"
        case .cloned: "internaldrive"
        case .databaseTools: "cylinder"
        case .backendTools: "server.rack"
        case .agentTools: "brain"
        case .codingAgentTools: "chevron.left.forwardslash.chevron.right"
        case .computerUseTools: "cursorarrow.click.2"
        case .aiMemoryTools: "memorychip"
        case .mcpTools: "puzzlepiece.extension"
        case .internalTools: "rectangle.grid.2x2"
        case .workspaceTools: "rectangle.3.group"
        case .knowledgeTools: "book"
        case .macOSTools: "macbook"
        case .swiftUITools: "swift"
        case .cliTools: "terminal"
        case .editorTools: "doc.text"
        case .devopsTools: "gearshape.2"
        case .automationTools: "arrow.triangle.2.circlepath"
        case .mediaTools: "photo.on.rectangle"
        case .designTools: "paintbrush"
        case .securityTools: "lock.shield"
        case .utilityTools: "wrench.and.screwdriver"
        case .frontendTools: "globe"
        case .gamesTools: "gamecontroller"
        case .localFirst: "house"
        case .settings: "gearshape"
        }
    }

    var section: SidebarSection {
        switch self {
        case .allProjects, .topShelf, .collector, .yardSale, .cloned:
            return .library
        case .databaseTools, .backendTools, .agentTools, .codingAgentTools,
             .computerUseTools, .aiMemoryTools, .mcpTools, .internalTools,
             .workspaceTools, .knowledgeTools, .macOSTools, .swiftUITools, .cliTools,
             .editorTools, .devopsTools, .automationTools, .mediaTools,
             .designTools, .securityTools, .utilityTools, .frontendTools,
             .gamesTools, .localFirst:
            return .categories
        case .settings:
            return .settings
        }
    }

    /// Top category filters shown in the sidebar (full taxonomy stays in CategoryClassifier).
    static let sidebarCategoryItems: [SidebarItem] = [
        .databaseTools, .backendTools, .agentTools, .codingAgentTools,
        .computerUseTools, .aiMemoryTools, .mcpTools, .internalTools,
        .workspaceTools, .knowledgeTools, .macOSTools, .swiftUITools, .cliTools, .editorTools,
        .devopsTools, .automationTools, .mediaTools, .designTools,
        .securityTools, .utilityTools, .frontendTools, .gamesTools, .localFirst,
    ]

    /// Items shown in the sidebar list (catalog filters only).
    static var sidebarCatalogItems: [SidebarItem] {
        [.allProjects, .topShelf, .collector, .yardSale, .cloned] + sidebarCategoryItems
    }

    /// Sidebar items that narrow the catalog list.
    var isCatalogFilter: Bool {
        switch self {
        case .allProjects, .settings:
            return false
        default:
            return true
        }
    }

    /// Whether a catalog row matches this sidebar filter (shared by list filtering and counts).
    func matchesCatalogFilter(_ project: ToolProject) -> Bool {
        switch self {
        case .allProjects, .settings:
            return true
        case .topShelf:
            return project.statusRaw == ProjectStatus.topShelf.rawValue
        case .collector:
            return project.statusRaw == ProjectStatus.collector.rawValue
        case .yardSale:
            return project.statusRaw == ProjectStatus.yardSale.rawValue
        case .cloned:
            return CatalogCloneService.isCloned(project)
        case .localFirst:
            return project.isLocalFirst
        default:
            return matchesCategory(project.category)
        }
    }

    /// Whether one category string belongs to this category filter.
    func matchesCategory(_ category: String) -> Bool {
        switch self {
        case .databaseTools: category.localizedStandardContains("Database")
        case .backendTools: category.localizedStandardContains("Backend")
        case .agentTools: category == "AI / Agent"
        case .codingAgentTools: category == "Coding Agents"
        case .computerUseTools: category == "Computer Use"
        case .aiMemoryTools: category == "AI Memory"
        case .mcpTools: category == "MCP"
        case .internalTools: category.localizedStandardContains("Internal Tools")
        case .workspaceTools: category.localizedStandardContains("Workspace")
        case .knowledgeTools: category.localizedStandardContains("Knowledge")
        case .macOSTools: category.localizedStandardContains("macOS")
        case .swiftUITools: category == "SwiftUI"
        case .cliTools: category.localizedStandardContains("CLI")
        case .editorTools: category.localizedStandardContains("Editor")
        case .devopsTools: category.localizedStandardContains("DevOps")
        case .automationTools: category.localizedStandardContains("Automation")
        case .mediaTools: category.localizedStandardContains("Media")
        case .designTools: category.localizedStandardContains("Design")
        case .securityTools: category.localizedStandardContains("Security")
        case .utilityTools: category.localizedStandardContains("Utility")
        case .frontendTools: category.localizedStandardContains("Frontend")
        case .gamesTools: category.localizedStandardContains("Games")
        default: false
        }
    }

    /// Category names a project can be filed under (the category filters,
    /// minus the Local-First flag, which isn't a category).
    static var assignableCategoryTitles: [String] {
        sidebarCategoryItems.filter { $0 != .localFirst }.map(\.title)
    }
}

enum SidebarSection: String {
    case library = "Library"
    case folders = "Folders"
    case categories = "Categories"
    case tags = "Tags"
    case settings = "Settings"
}
