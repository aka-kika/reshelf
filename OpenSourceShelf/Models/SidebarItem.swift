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
    case queue = "queue"
    case compare = "compare"
    case ecosystems = "ecosystems"
    case workflows = "workflows"
    case myStack = "myStack"

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
        case .queue: "Queue"
        case .compare: "Compare"
        case .ecosystems: "Ecosystems"
        case .workflows: "Workflows"
        case .myStack: "My Stack"
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
        case .queue: "tray.full"
        case .compare: "arrow.left.arrow.right"
        case .ecosystems: "circle.hexagongrid"
        case .workflows: "point.3.connected.trianglepath.dotted"
        case .myStack: "square.stack.3d.up"
        case .settings: "gearshape"
        }
    }

    var section: SidebarSection {
        switch self {
        case .allProjects, .topShelf, .collector, .yardSale, .cloned:
            return .library
        case .databaseTools, .backendTools, .agentTools, .codingAgentTools,
             .computerUseTools, .aiMemoryTools, .mcpTools, .internalTools,
             .workspaceTools, .knowledgeTools, .macOSTools, .cliTools,
             .editorTools, .devopsTools, .automationTools, .mediaTools,
             .designTools, .securityTools, .utilityTools, .frontendTools,
             .gamesTools, .localFirst:
            return .categories
        case .queue, .compare, .ecosystems, .workflows, .myStack:
            return .library
        case .settings:
            return .settings
        }
    }

    /// Top category filters shown in the sidebar (full taxonomy stays in CategoryClassifier).
    static let sidebarCategoryItems: [SidebarItem] = [
        .databaseTools, .backendTools, .agentTools, .codingAgentTools,
        .computerUseTools, .aiMemoryTools, .mcpTools, .internalTools,
        .workspaceTools, .knowledgeTools, .macOSTools, .cliTools, .editorTools,
        .devopsTools, .automationTools, .mediaTools, .designTools,
        .securityTools, .utilityTools, .frontendTools, .gamesTools, .localFirst,
    ]

    /// Items shown in the sidebar list (catalog filters only).
    static var sidebarCatalogItems: [SidebarItem] {
        [.allProjects, .topShelf, .collector, .yardSale, .cloned] + sidebarCategoryItems
    }

    /// Sidebar items that narrow the catalog list (not Queue, Compare, etc.).
    var isCatalogFilter: Bool {
        switch self {
        case .allProjects, .queue, .compare, .ecosystems, .workflows, .myStack, .settings:
            return false
        default:
            return true
        }
    }

    /// Whether a catalog row matches this sidebar filter (shared by list filtering and counts).
    func matchesCatalogFilter(_ project: ToolProject) -> Bool {
        switch self {
        case .allProjects, .queue, .compare, .ecosystems, .workflows, .myStack, .settings:
            return true
        case .topShelf:
            return project.statusRaw == ProjectStatus.topShelf.rawValue
        case .collector:
            return project.statusRaw == ProjectStatus.collector.rawValue
        case .yardSale:
            return project.statusRaw == ProjectStatus.yardSale.rawValue
        case .cloned:
            return CatalogCloneService.isCloned(project)
        case .databaseTools:
            return project.category.localizedStandardContains("Database")
        case .backendTools:
            return project.category.localizedStandardContains("Backend")
        case .agentTools:
            return project.category == "AI / Agent"
        case .codingAgentTools:
            return project.category == "Coding Agents"
        case .computerUseTools:
            return project.category == "Computer Use"
        case .aiMemoryTools:
            return project.category == "AI Memory"
        case .mcpTools:
            return project.category == "MCP"
        case .internalTools:
            return project.category.localizedStandardContains("Internal Tools")
        case .workspaceTools:
            return project.category.localizedStandardContains("Workspace")
        case .knowledgeTools:
            return project.category.localizedStandardContains("Knowledge")
        case .macOSTools:
            return project.category.localizedStandardContains("macOS")
        case .cliTools:
            return project.category.localizedStandardContains("CLI")
        case .editorTools:
            return project.category.localizedStandardContains("Editor")
        case .devopsTools:
            return project.category.localizedStandardContains("DevOps")
        case .automationTools:
            return project.category.localizedStandardContains("Automation")
        case .mediaTools:
            return project.category.localizedStandardContains("Media")
        case .designTools:
            return project.category.localizedStandardContains("Design")
        case .securityTools:
            return project.category.localizedStandardContains("Security")
        case .utilityTools:
            return project.category.localizedStandardContains("Utility")
        case .frontendTools:
            return project.category.localizedStandardContains("Frontend")
        case .gamesTools:
            return project.category.localizedStandardContains("Games")
        case .localFirst:
            return project.isLocalFirst
        }
    }

    func predicate() -> Predicate<ToolProject>? {
        switch self {
        case .allProjects: return nil
        case .topShelf: return #Predicate { $0.statusRaw == "topShelf" }
        case .collector: return #Predicate { $0.statusRaw == "collector" }
        case .yardSale: return #Predicate { $0.statusRaw == "yardSale" }
        // Filesystem-derived (no stored field) — filtered in-memory via matchesCatalogFilter.
        case .cloned: return nil
        case .databaseTools: return #Predicate { $0.category.localizedStandardContains("Database") }
        case .backendTools: return #Predicate { $0.category.localizedStandardContains("Backend") }
        case .agentTools: return #Predicate { $0.category == "AI / Agent" }
        case .codingAgentTools: return #Predicate { $0.category == "Coding Agents" }
        case .computerUseTools: return #Predicate { $0.category == "Computer Use" }
        case .aiMemoryTools: return #Predicate { $0.category == "AI Memory" }
        case .mcpTools: return #Predicate { $0.category == "MCP" }
        case .internalTools: return #Predicate { $0.category.localizedStandardContains("Internal Tools") }
        case .workspaceTools: return #Predicate { $0.category.localizedStandardContains("Workspace") }
        case .knowledgeTools: return #Predicate { $0.category.localizedStandardContains("Knowledge") }
        case .macOSTools: return #Predicate { $0.category.localizedStandardContains("macOS") }
        case .cliTools: return #Predicate { $0.category.localizedStandardContains("CLI") }
        case .editorTools: return #Predicate { $0.category.localizedStandardContains("Editor") }
        case .devopsTools: return #Predicate { $0.category.localizedStandardContains("DevOps") }
        case .automationTools: return #Predicate { $0.category.localizedStandardContains("Automation") }
        case .mediaTools: return #Predicate { $0.category.localizedStandardContains("Media") }
        case .designTools: return #Predicate { $0.category.localizedStandardContains("Design") }
        case .securityTools: return #Predicate { $0.category.localizedStandardContains("Security") }
        case .utilityTools: return #Predicate { $0.category.localizedStandardContains("Utility") }
        case .frontendTools: return #Predicate { $0.category.localizedStandardContains("Frontend") }
        case .gamesTools: return #Predicate { $0.category.localizedStandardContains("Games") }
        case .localFirst: return #Predicate { $0.isLocalFirst == true }
        case .queue, .compare, .ecosystems, .workflows, .myStack, .settings: return nil
        }
    }
}

enum SidebarSection: String {
    case library = "Library"
    case categories = "Categories"
    case settings = "Settings"
}
