import Foundation

enum RunbookCommandExtractor {
    static func extract(from evidence: RunbookEvidence, fileManager: FileManager = .default) -> RunbookCommandSet {
        var commands = RunbookCommandSet()

        let manifestTypes = Set(evidence.manifests.map(\.type))
        let hasPNPM = manifestTypes.contains("pnpm_lock") || evidence.manifests.contains { $0.path.contains("pnpm-lock") }
        let hasYarn = manifestTypes.contains("yarn_lock")
        let hasBun = manifestTypes.contains("bun_lock")

        if manifestTypes.contains("package_json") {
            let pm = hasPNPM ? "pnpm" : (hasYarn ? "yarn" : (hasBun ? "bun" : "npm"))
            commands.installCommands.append(RunbookCommand(command: "\(pm) install",
                                                           source: "package.json ecosystem",
                                                           confidence: "medium"))
            if let packageJSON = evidence.manifests.first(where: { $0.type == "package_json" }),
               let scripts = parsePackageScripts(from: packageJSON.evidenceText) {
                appendScriptCommands(scripts, packageManager: pm, into: &commands)
            }
        }

        if manifestTypes.contains("requirements") {
            commands.installCommands.append(RunbookCommand(command: "python -m venv .venv",
                                                           source: "requirements.txt",
                                                           confidence: "medium"))
            commands.installCommands.append(RunbookCommand(command: "source .venv/bin/activate && pip install -r requirements.txt",
                                                           source: "requirements.txt",
                                                           confidence: "medium"))
        }

        if manifestTypes.contains("pyproject") {
            commands.installCommands.append(RunbookCommand(command: "python -m venv .venv",
                                                           source: "pyproject.toml",
                                                           confidence: "medium"))
            commands.installCommands.append(RunbookCommand(command: "source .venv/bin/activate && pip install -e .",
                                                           source: "pyproject.toml",
                                                           confidence: "low"))
        }

        if manifestTypes.contains("cargo_toml") {
            commands.installCommands.append(RunbookCommand(command: "cargo build",
                                                           source: "Cargo.toml",
                                                           confidence: "medium"))
            commands.runCommands.append(RunbookCommand(command: "cargo run",
                                                       source: "Cargo.toml",
                                                       confidence: "medium"))
        }

        if manifestTypes.contains("go_module") {
            commands.installCommands.append(RunbookCommand(command: "go mod download",
                                                           source: "go.mod",
                                                           confidence: "medium"))
            commands.runCommands.append(RunbookCommand(command: "go run .",
                                                       source: "go.mod",
                                                       confidence: "low"))
        }

        if manifestTypes.contains("swift_package") {
            commands.installCommands.append(RunbookCommand(command: "swift build",
                                                           source: "Package.swift",
                                                           confidence: "medium"))
            commands.runCommands.append(RunbookCommand(command: "swift run",
                                                       source: "Package.swift",
                                                       confidence: "medium"))
        }

        if manifestTypes.contains("docker_compose") {
            commands.dockerCommands.append(RunbookCommand(command: "docker compose up",
                                                          source: "docker-compose.yml / compose.yaml",
                                                          confidence: "medium"))
        } else if manifestTypes.contains("dockerfile") {
            commands.dockerCommands.append(RunbookCommand(command: "docker build -t local-test .",
                                                          source: "Dockerfile",
                                                          confidence: "low"))
            commands.dockerCommands.append(RunbookCommand(command: "docker run --rm local-test",
                                                          source: "Dockerfile",
                                                          confidence: "low"))
        }

        if let clonePath = evidence.clonePath {
            let root = URL(fileURLWithPath: clonePath, isDirectory: true)
            appendClonePathCommands(at: root, manifestTypes: manifestTypes, fileManager: fileManager, into: &commands)
            appendEnvExamples(at: root, fileManager: fileManager, into: &commands)
        }

        if let readme = evidence.readmeExcerpt {
            appendReadmeCommands(from: readme, into: &commands)
        }

        return dedupe(commands)
    }

    private static func appendClonePathCommands(at root: URL,
                                                manifestTypes: Set<String>,
                                                fileManager: FileManager,
                                                into commands: inout RunbookCommandSet) {
        for name in ["Makefile", "makefile", "GNUmakefile"] {
            let url = root.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                appendMakefileTargets(from: text, into: &commands)
                break
            }
        }

        if !manifestTypes.contains("package_json") {
            let packageURL = root.appendingPathComponent("package.json")
            if fileManager.fileExists(atPath: packageURL.path),
               let text = try? String(contentsOf: packageURL, encoding: .utf8),
               let scripts = parsePackageScripts(from: text) {
                appendScriptCommands(scripts, packageManager: "npm", into: &commands)
                if commands.installCommands.isEmpty {
                    commands.installCommands.append(RunbookCommand(command: "npm install",
                                                                   source: "package.json",
                                                                   confidence: "medium"))
                }
            }
        }
    }

    private static func parsePackageScripts(from evidenceText: String?) -> [String: String]? {
        guard let evidenceText,
              let data = evidenceText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String] else {
            return nil
        }
        return scripts
    }

    private static func appendScriptCommands(_ scripts: [String: String],
                                             packageManager: String,
                                             into commands: inout RunbookCommandSet) {
        let runKeys = ["dev", "start", "serve", "preview"]
        let buildKeys = ["build", "test", "lint"]

        for key in runKeys {
            guard scripts[key] != nil else { continue }
            let cmd = packageManager == "yarn" ? "yarn \(key)" : "\(packageManager) run \(key)"
            commands.runCommands.append(RunbookCommand(command: cmd,
                                                       source: "package.json scripts.\(key)",
                                                       confidence: "high"))
        }

        for key in buildKeys {
            guard scripts[key] != nil else { continue }
            let cmd = packageManager == "yarn" ? "yarn \(key)" : "\(packageManager) run \(key)"
            commands.runCommands.append(RunbookCommand(command: cmd,
                                                       source: "package.json scripts.\(key)",
                                                       confidence: "high"))
        }
    }

    private static func appendMakefileTargets(from text: String, into commands: inout RunbookCommandSet) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(":"), !trimmed.hasPrefix("#"), !trimmed.hasPrefix(".") else { continue }
            let name = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            let target = name.trimmingCharacters(in: .whitespaces)
            guard ["install", "setup", "dev", "run", "start", "build", "test"].contains(target.lowercased()) else {
                continue
            }
            let entry = RunbookCommand(command: "make \(target)",
                                       source: "Makefile target \(target)",
                                       confidence: "high")
            if ["install", "setup"].contains(target.lowercased()) {
                commands.installCommands.append(entry)
            } else {
                commands.runCommands.append(entry)
            }
        }
    }

    private static func appendReadmeCommands(from readme: String, into commands: inout RunbookCommandSet) {
        let patterns = [
            #"```(?:bash|sh|shell|zsh)?\s*([\s\S]*?)```"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(readme.startIndex..<readme.endIndex, in: readme)
            regex.enumerateMatches(in: readme, options: [], range: range) { match, _, _ in
                guard let match,
                      match.numberOfRanges > 1,
                      let swiftRange = Range(match.range(at: 1), in: readme) else { return }
                let block = String(readme[swiftRange])
                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard looksLikeCommand(trimmed) else { continue }
                    classifyReadmeCommand(String(trimmed), into: &commands)
                }
            }
        }
    }

    private static func looksLikeCommand(_ line: String) -> Bool {
        let prefixes = ["npm ", "pnpm ", "yarn ", "bun ", "cargo ", "go ", "swift ", "docker ", "pip ", "python ", "make "]
        return prefixes.contains { line.hasPrefix($0) } || line.hasPrefix("#")
    }

    private static func classifyReadmeCommand(_ command: String, into commands: inout RunbookCommandSet) {
        let lowered = command.lowercased()
        let entry = RunbookCommand(command: command,
                                   source: "README excerpt",
                                   confidence: "medium")
        if lowered.contains("install") || lowered.contains("mod download") {
            commands.installCommands.append(entry)
        } else if lowered.hasPrefix("docker") {
            commands.dockerCommands.append(entry)
        } else {
            commands.runCommands.append(entry)
        }
    }

    private static func appendEnvExamples(at rootURL: URL,
                                          fileManager: FileManager,
                                          into commands: inout RunbookCommandSet) {
        let names = [".env.example", ".env.sample", "env.example", ".env.template"]
        for name in names {
            let url = rootURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let excerpt = text.split(separator: "\n").prefix(12).joined(separator: "\n")
            commands.environmentNotes.append("Example from \(name):\n\(excerpt)")
        }
    }

    private static func dedupe(_ commands: RunbookCommandSet) -> RunbookCommandSet {
        func unique(_ items: [RunbookCommand]) -> [RunbookCommand] {
            var seen: Set<String> = []
            return items.filter { item in
                let key = item.command.lowercased()
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
        }

        return RunbookCommandSet(installCommands: unique(commands.installCommands),
                                 runCommands: unique(commands.runCommands),
                                 dockerCommands: unique(commands.dockerCommands),
                                 environmentNotes: Array(Set(commands.environmentNotes)).sorted())
    }
}
