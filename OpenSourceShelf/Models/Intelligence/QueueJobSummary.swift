import Foundation
import GRDB

struct QueueJobSummary: Identifiable, Equatable {
    var id: String
    var repositoryID: String?
    var repositoryFullName: String?
    var repositoryName: String?
    var type: String
    var status: String
    var priority: Int
    var progress: Double
    var error: String?
    var createdAt: String
    var startedAt: String?
    var completedAt: String?
    var cloneStatus: String?
    var clonePath: String?
    var cloneLastError: String?

    init(row: Row) {
        id = row["id"]
        repositoryID = row["repository_id"]
        repositoryFullName = row["repository_full_name"]
        repositoryName = row["repository_name"]
        type = row["type"]
        status = row["status"]
        priority = row["priority"]
        progress = row["progress"]
        error = row["error"]
        createdAt = row["created_at"]
        startedAt = row["started_at"]
        completedAt = row["completed_at"]
        cloneStatus = row["clone_status"]
        clonePath = row["clone_path"]
        cloneLastError = row["clone_last_error"]
    }

    var displayRepositoryName: String {
        if type == "ecosystem_discovery" || type == "refresh_graph_cache" || type == "refresh_graph_navigation_cache" || type == "refresh_graph_paths" {
            return "Shelf intelligence"
        }
        return repositoryFullName ?? repositoryName ?? "Unknown repository"
    }

    var displayType: String {
        switch type {
        case "fetch_github_metadata":
            return "GitHub metadata"
        case "clone_repo":
            return "Clone"
        case "static_analysis":
            if status == "completed" {
                return "Completed analysis"
            }
            if progress < 0.35 {
                return "Analyzing manifests"
            }
            if progress < 0.7 {
                return "Detecting stack"
            }
            return "Persisting analysis"
        case "ai_analysis":
            if status == "completed" {
                return "Completed AI summary"
            }
            if progress < 0.35 {
                return "Analyzing static evidence"
            }
            if progress < 0.75 {
                return "Generating AI summary"
            }
            return "Persisting intelligence"
        case "relationship_generation":
            if status == "completed" {
                return "Relationships complete"
            }
            return "Generating relationships"
        case "recommendation_generation":
            if status == "completed" {
                return "Recommendations complete"
            }
            if progress < 0.45 {
                return "Scoring graph signals"
            }
            if progress < 0.8 {
                return "Ranking recommendations"
            }
            return "Persisting recommendations"
        case "ecosystem_discovery":
            if status == "completed" {
                return "Ecosystems complete"
            }
            if progress < 0.45 {
                return "Generating ecosystems"
            }
            if progress < 0.85 {
                return "Clustering workflows"
            }
            return "Persisting ecosystems"
        case "refresh_graph_layout":
            if status == "completed" {
                return "Graph layout ready"
            }
            return progress < 0.5 ? "Loading neighborhood" : "Computing layout"
        case "refresh_graph_cache":
            return status == "completed" ? "Graph cache cleared" : "Refreshing graph cache"
        case "refresh_graph_navigation_cache":
            return status == "completed" ? "Graph navigation ready" : "Refreshing graph navigation cache"
        case "refresh_graph_paths":
            return status == "completed" ? "Graph paths ready" : "Refreshing graph path cache"
        case "generate_runbook":
            if status == "pending" {
                return "Queued runbook generation"
            }
            if status == "completed" {
                return "Runbook complete"
            }
            if status == "failed" {
                return "Runbook failed"
            }
            if progress < 0.45 {
                return "Generating runbook"
            }
            return progress < 0.75 ? "Organizing runbook" : "Persisting runbook"
        default:
            return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var displayError: String? {
        if type == "clone_repo" {
            return cloneLastError ?? error
        }
        return error
    }

    var canCancel: Bool {
        status == "pending" || status == "running"
    }

    var canRetry: Bool {
        status == "failed"
    }
}
