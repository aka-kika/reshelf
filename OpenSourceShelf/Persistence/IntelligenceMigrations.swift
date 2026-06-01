import Foundation
import GRDB

enum IntelligenceMigrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_intelligence_foundation") { db in
            try db.create(table: "repositories") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("host", .text).notNull()
                table.column("owner", .text).notNull()
                table.column("name", .text).notNull()
                table.column("full_name", .text).notNull().unique()
                table.column("github_url", .text).notNull().unique()
                table.column("website_url", .text)
                table.column("default_branch", .text)
                table.column("local_path", .text)
                table.column("latest_commit_sha", .text)
                table.column("user_status", .text).notNull().defaults(to: "new")
                table.column("added_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("last_analyzed_at", .text)
            }

            try db.create(table: "repository_metadata") { table in
                table.column("repository_id", .text)
                    .notNull()
                    .primaryKey()
                    .references("repositories", onDelete: .cascade)
                table.column("description", .text)
                table.column("stars", .integer)
                table.column("forks", .integer)
                table.column("open_issues", .integer)
                table.column("license_spdx", .text)
                table.column("topics_json", .text).notNull().defaults(to: "[]")
                table.column("primary_language", .text)
                table.column("pushed_at", .text)
                table.column("archived", .boolean).notNull().defaults(to: false)
                table.column("fork", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "clone_states") { table in
                table.column("repository_id", .text)
                    .notNull()
                    .primaryKey()
                    .references("repositories", onDelete: .cascade)
                table.column("status", .text).notNull()
                table.column("clone_mode", .text).notNull()
                table.column("path", .text)
                table.column("current_head", .text)
                table.column("branch_count", .integer)
                table.column("tag_count", .integer)
                table.column("size_bytes", .integer)
                table.column("last_fetch_at", .text)
                table.column("last_error", .text)
            }

            try db.create(table: "ingestion_jobs") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text)
                    .references("repositories", onDelete: .setNull)
                table.column("type", .text).notNull()
                table.column("status", .text).notNull()
                table.column("priority", .integer).notNull().defaults(to: 0)
                table.column("progress", .double).notNull().defaults(to: 0)
                table.column("error", .text)
                table.column("created_at", .text).notNull()
                table.column("started_at", .text)
                table.column("completed_at", .text)
            }

            try db.create(index: "idx_ingestion_jobs_status_priority",
                          on: "ingestion_jobs",
                          columns: ["status", "priority", "created_at"])
            try db.create(index: "idx_repositories_owner_name",
                          on: "repositories",
                          columns: ["owner", "name"])
        }

        migrator.registerMigration("v2_static_intelligence") { db in
            try db.create(table: "repository_files") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text)
                    .notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("path", .text).notNull()
                table.column("file_type", .text).notNull()
                table.column("category", .text).notNull()
                table.column("size_bytes", .integer)
                table.column("detected_at", .text).notNull()
                table.uniqueKey(["repository_id", "path"])
            }

            try db.create(table: "repository_manifests") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text)
                    .notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("path", .text).notNull()
                table.column("type", .text).notNull()
                table.column("ecosystem", .text).notNull()
                table.column("evidence_text", .text)
                table.column("detected_at", .text).notNull()
                table.uniqueKey(["repository_id", "path", "type"])
            }

            try db.create(table: "detected_stack_items") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text)
                    .notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("category", .text).notNull()
                table.column("detection_source", .text).notNull()
                table.column("confidence", .double).notNull()
                table.column("evidence_path", .text)
                table.column("evidence_text", .text)
                table.column("detected_at", .text).notNull()
                table.uniqueKey(["repository_id", "name", "category", "evidence_path"])
            }

            try db.create(index: "idx_repository_files_repository",
                          on: "repository_files",
                          columns: ["repository_id", "category"])
            try db.create(index: "idx_repository_manifests_repository",
                          on: "repository_manifests",
                          columns: ["repository_id", "ecosystem"])
            try db.create(index: "idx_detected_stack_items_repository",
                          on: "detected_stack_items",
                          columns: ["repository_id", "category", "name"])
        }

        migrator.registerMigration("v3_lightweight_ai_intelligence") { db in
            try db.create(table: "ai_insights") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text)
                    .notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("cache_key", .text).notNull().unique()
                table.column("model_name", .text).notNull()
                table.column("prompt_version", .text).notNull()
                table.column("commit_sha", .text)
                table.column("summary", .text).notNull()
                table.column("usefulness", .text).notNull()
                table.column("classifications_json", .text).notNull().defaults(to: "[]")
                table.column("risks_json", .text).notNull().defaults(to: "[]")
                table.column("relationship_hints_json", .text).notNull().defaults(to: "[]")
                table.column("raw_json", .text).notNull()
                table.column("generated_at", .text).notNull()
            }

            try db.create(table: "repository_scores") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text)
                    .notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("cache_key", .text)
                    .notNull()
                    .unique()
                    .references("ai_insights", column: "cache_key", onDelete: .cascade)
                table.column("setup_complexity", .integer).notNull()
                table.column("local_first_score", .integer).notNull()
                table.column("experimentation_priority", .integer).notNull()
                table.column("ecosystem_influence", .integer).notNull()
                table.column("personal_relevance", .integer).notNull()
                table.column("generated_at", .text).notNull()
            }

            try db.create(index: "idx_ai_insights_repository_generated",
                          on: "ai_insights",
                          columns: ["repository_id", "generated_at"])
            try db.create(index: "idx_repository_scores_repository",
                          on: "repository_scores",
                          columns: ["repository_id", "generated_at"])
        }

        migrator.registerMigration("v4_graph_persistence") { db in
            try db.create(table: "graph_nodes") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("type", .text).notNull()
                table.column("key", .text).notNull().unique()
                table.column("label", .text).notNull()
                table.column("metadata_json", .text).notNull().defaults(to: "{}")
            }

            try db.create(table: "graph_edges") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("source_node_id", .text)
                    .notNull()
                    .references("graph_nodes", onDelete: .cascade)
                table.column("target_node_id", .text)
                    .notNull()
                    .references("graph_nodes", onDelete: .cascade)
                table.column("relationship_type", .text).notNull()
                table.column("confidence", .double).notNull()
                table.column("evidence_text", .text)
                table.column("evidence_path", .text)
                table.column("created_by", .text).notNull()
                table.column("created_at", .text).notNull()
                table.uniqueKey(["source_node_id", "target_node_id", "relationship_type"])
            }

            try db.create(index: "idx_graph_nodes_type_key",
                          on: "graph_nodes",
                          columns: ["type", "key"])
            try db.create(index: "idx_graph_edges_source_type",
                          on: "graph_edges",
                          columns: ["source_node_id", "relationship_type"])
            try db.create(index: "idx_graph_edges_target_type",
                          on: "graph_edges",
                          columns: ["target_node_id", "relationship_type"])
            try db.create(index: "idx_graph_edges_relationship",
                          on: "graph_edges",
                          columns: ["relationship_type", "confidence"])
        }

        migrator.registerMigration("v5_recommendations") { db in
            try db.create(table: "repository_recommendations") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("source_repository_id", .text)
                    .notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("target_node_id", .text)
                    .notNull()
                    .references("graph_nodes", onDelete: .cascade)
                table.column("target_repository_id", .text)
                    .references("repositories", onDelete: .cascade)
                table.column("recommendation_type", .text).notNull()
                table.column("score", .double).notNull()
                table.column("explanation", .text).notNull()
                table.column("signals_json", .text).notNull().defaults(to: "[]")
                table.column("cache_key", .text).notNull()
                table.column("generated_at", .text).notNull()
                table.uniqueKey(["source_repository_id", "target_node_id", "recommendation_type"])
            }

            try db.create(index: "idx_repository_recommendations_source_type",
                          on: "repository_recommendations",
                          columns: ["source_repository_id", "recommendation_type", "score"])
            try db.create(index: "idx_repository_recommendations_cache",
                          on: "repository_recommendations",
                          columns: ["source_repository_id", "cache_key"])
            try db.create(index: "idx_repository_recommendations_target_repository",
                          on: "repository_recommendations",
                          columns: ["target_repository_id"])
        }

        migrator.registerMigration("v6_ecosystem_discovery") { db in
            try db.create(table: "ecosystem_clusters") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("cluster_type", .text).notNull()
                table.column("name", .text).notNull()
                table.column("score", .double).notNull()
                table.column("confidence", .double).notNull()
                table.column("repository_ids_json", .text).notNull().defaults(to: "[]")
                table.column("repository_names_json", .text).notNull().defaults(to: "[]")
                table.column("common_stack_json", .text).notNull().defaults(to: "[]")
                table.column("strongest_tools_json", .text).notNull().defaults(to: "[]")
                table.column("integrations_json", .text).notNull().defaults(to: "[]")
                table.column("recommendation_highlights_json", .text).notNull().defaults(to: "[]")
                table.column("missing_pieces_json", .text).notNull().defaults(to: "[]")
                table.column("signals_json", .text).notNull().defaults(to: "[]")
                table.column("explanation", .text).notNull()
                table.column("cache_key", .text).notNull()
                table.column("generated_at", .text).notNull()
                table.uniqueKey(["cluster_type", "name"])
            }

            try db.create(index: "idx_ecosystem_clusters_type_score",
                          on: "ecosystem_clusters",
                          columns: ["cluster_type", "score"])
            try db.create(index: "idx_ecosystem_clusters_cache",
                          on: "ecosystem_clusters",
                          columns: ["cache_key"])
        }

        migrator.registerMigration("v7_natural_language_exploration") { db in
            try db.create(table: "exploration_index_entries") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("entry_type", .text).notNull()
                table.column("target_id", .text).notNull()
                table.column("repository_id", .text)
                    .references("repositories", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("subtitle", .text).notNull()
                table.column("body", .text).notNull()
                table.column("ecosystem_name", .text)
                table.column("keywords_json", .text).notNull().defaults(to: "[]")
                table.column("signals_json", .text).notNull().defaults(to: "[]")
                table.column("score", .double).notNull()
                table.column("confidence", .double).notNull()
                table.column("cache_key", .text).notNull()
                table.column("generated_at", .text).notNull()
                table.uniqueKey(["entry_type", "target_id"])
            }

            try db.create(table: "exploration_queries") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("query_text", .text).notNull()
                table.column("normalized_intent", .text).notNull()
                table.column("filters_json", .text).notNull().defaults(to: "[]")
                table.column("result_ids_json", .text).notNull().defaults(to: "[]")
                table.column("is_favorite", .boolean).notNull().defaults(to: false)
                table.column("created_at", .text).notNull()
                table.column("last_used_at", .text).notNull()
                table.uniqueKey(["query_text"])
            }

            try db.create(index: "idx_exploration_entries_type_score",
                          on: "exploration_index_entries",
                          columns: ["entry_type", "score"])
            try db.create(index: "idx_exploration_entries_cache",
                          on: "exploration_index_entries",
                          columns: ["cache_key"])
            try db.create(index: "idx_exploration_queries_recent",
                          on: "exploration_queries",
                          columns: ["last_used_at"])
        }

        migrator.registerMigration("v8_semantic_search_embeddings") { db in
            try db.create(table: "embedding_chunks") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text).notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("source_type", .text).notNull()
                table.column("source_path", .text).notNull().defaults(to: "")
                table.column("chunk_text", .text).notNull()
                table.column("content_hash", .text).notNull()
                table.column("embedding_model", .text).notNull()
                table.column("embedding", .blob).notNull()
                table.column("created_at", .text).notNull()
                table.uniqueKey(["repository_id", "source_type", "source_path", "content_hash", "embedding_model"])
            }

            try db.create(table: "semantic_search_cache") { table in
                table.column("query_hash", .text).notNull().primaryKey()
                table.column("query_text", .text).notNull()
                table.column("results_json", .text).notNull().defaults(to: "[]")
                table.column("created_at", .text).notNull()
            }

            try db.create(index: "idx_embedding_chunks_repo_model",
                          on: "embedding_chunks",
                          columns: ["repository_id", "embedding_model"])
            try db.create(index: "idx_embedding_chunks_model",
                          on: "embedding_chunks",
                          columns: ["embedding_model"])
            try db.create(index: "idx_semantic_search_cache_created",
                          on: "semantic_search_cache",
                          columns: ["created_at"])
        }

        migrator.registerMigration("v9_graph_layout_cache") { db in
            try db.create(table: "graph_layout_cache") { table in
                table.column("focus_repository_id", .text).notNull().primaryKey()
                    .references("repositories", onDelete: .cascade)
                table.column("cache_key", .text).notNull()
                table.column("layout_json", .text).notNull().defaults(to: "{}")
                table.column("created_at", .text).notNull()
            }

            try db.create(index: "idx_graph_layout_cache_key",
                          on: "graph_layout_cache",
                          columns: ["cache_key"])
        }

        migrator.registerMigration("v10_graph_search_cache") { db in
            try db.create(table: "graph_path_cache") { table in
                table.column("cache_key", .text).notNull().primaryKey()
                table.column("path_json", .text).notNull().defaults(to: "{}")
                table.column("created_at", .text).notNull()
            }

            try db.create(table: "graph_navigation_cache") { table in
                table.column("cache_id", .text).notNull().primaryKey()
                table.column("payload_json", .text).notNull().defaults(to: "{}")
                table.column("updated_at", .text).notNull()
            }

            try db.create(index: "idx_graph_path_cache_created",
                          on: "graph_path_cache",
                          columns: ["created_at"])
        }

        migrator.registerMigration("v11_compare_cache") { db in
            try db.create(table: "comparison_sessions") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_ids_json", .text).notNull().defaults(to: "[]")
                table.column("title", .text)
                table.column("is_favorite", .boolean).notNull().defaults(to: false)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "comparison_results_cache") { table in
                table.column("cache_signature", .text).notNull().primaryKey()
                table.column("repository_ids_json", .text).notNull().defaults(to: "[]")
                table.column("result_json", .text).notNull().defaults(to: "{}")
                table.column("created_at", .text).notNull()
            }

            try db.create(index: "idx_comparison_sessions_updated",
                          on: "comparison_sessions",
                          columns: ["updated_at"])
            try db.create(index: "idx_comparison_results_created",
                          on: "comparison_results_cache",
                          columns: ["created_at"])
        }

        migrator.registerMigration("v12_repository_runbooks") { db in
            try db.create(table: "repository_runbooks") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("repository_id", .text).notNull()
                    .references("repositories", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("summary", .text)
                table.column("markdown", .text).notNull()
                table.column("evidence_signature", .text).notNull()
                table.column("generated_by", .text).notNull()
                table.column("model_name", .text)
                table.column("prompt_version", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(index: "idx_repository_runbooks_repository",
                          on: "repository_runbooks",
                          columns: ["repository_id"])
            try db.create(index: "idx_repository_runbooks_evidence",
                          on: "repository_runbooks",
                          columns: ["evidence_signature"])
            try db.create(index: "idx_repository_runbooks_updated",
                          on: "repository_runbooks",
                          columns: ["updated_at"])
        }

        migrator.registerMigration("v13_runbook_freshness_metadata") { db in
            try db.alter(table: "repository_runbooks") { table in
                table.add(column: "evidence_components_json", .text)
                table.add(column: "last_exported_at", .text)
            }
        }

        return migrator
    }
}
