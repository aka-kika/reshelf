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
    case agentTools = "agentTools"
    case macOSTools = "macOSTools"
    case workspaceTools = "workspaceTools"
    case knowledgeTools = "knowledgeTools"
    case cliTools = "cliTools"
    case devopsTools = "devopsTools"
    case editorTools = "editorTools"
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
        case .databaseTools: "Database Tools"
        case .agentTools: "Agent Tools"
        case .macOSTools: "macOS Tools"
        case .workspaceTools: "Workspace"
        case .knowledgeTools: "Knowledge"
        case .cliTools: "CLI"
        case .devopsTools: "DevOps"
        case .editorTools: "Editor"
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
        case .agentTools: "brain"
        case .macOSTools: "macbook"
        case .workspaceTools: "rectangle.3.group"
        case .knowledgeTools: "book"
        case .cliTools: "terminal"
        case .devopsTools: "gearshape.2"
        case .editorTools: "doc.text"
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
        case .databaseTools, .agentTools, .macOSTools,
             .workspaceTools, .knowledgeTools, .cliTools, .devopsTools,
             .editorTools, .localFirst:
            return .categories
        case .queue, .compare, .ecosystems, .workflows, .myStack:
            return .library
        case .settings:
            return .settings
        }
    }

    /// Top category filters shown in the sidebar (full taxonomy stays in CategoryClassifier).
    static let sidebarCategoryItems: [SidebarItem] = [
        .databaseTools, .agentTools, .macOSTools,
        .workspaceTools, .knowledgeTools, .cliTools, .devopsTools, .editorTools,
        .localFirst,
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
        case .agentTools:
            return project.category.localizedStandardContains("Agent")
                || project.category.localizedStandardContains("AI")
        case .macOSTools:
            return project.category.localizedStandardContains("macOS")
        case .workspaceTools:
            return project.category.localizedStandardContains("Workspace")
        case .knowledgeTools:
            return project.category.localizedStandardContains("Knowledge")
        case .cliTools:
            return project.category.localizedStandardContains("CLI")
        case .devopsTools:
            return project.category.localizedStandardContains("DevOps")
        case .editorTools:
            return project.category.localizedStandardContains("Editor")
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
        case .agentTools: return #Predicate { $0.category.localizedStandardContains("Agent") || $0.category.localizedStandardContains("AI") }
        case .macOSTools: return #Predicate { $0.category.localizedStandardContains("macOS") }
        case .workspaceTools: return #Predicate { $0.category.localizedStandardContains("Workspace") }
        case .knowledgeTools: return #Predicate { $0.category.localizedStandardContains("Knowledge") }
        case .cliTools: return #Predicate { $0.category.localizedStandardContains("CLI") }
        case .devopsTools: return #Predicate { $0.category.localizedStandardContains("DevOps") }
        case .editorTools: return #Predicate { $0.category.localizedStandardContains("Editor") }
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
