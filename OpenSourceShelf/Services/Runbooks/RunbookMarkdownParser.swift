import Foundation

enum RunbookMarkdownBlock: Equatable, Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case codeBlock(language: String?, code: String)
    case blockquote(text: String)
    case horizontalRule

    var id: String {
        switch self {
        case .heading(let level, let text):
            return "h\(level)-\(text)"
        case .paragraph(let text):
            return "p-\(text.prefix(40))"
        case .bulletList(let items):
            return "ul-\(items.joined(separator: "|").prefix(40))"
        case .codeBlock(_, let code):
            return "code-\(code.prefix(40))"
        case .blockquote(let text):
            return "quote-\(text.prefix(40))"
        case .horizontalRule:
            return "hr"
        }
    }
}

enum RunbookMarkdownParser {
    static func parse(_ markdown: String) -> [RunbookMarkdownBlock] {
        var blocks: [RunbookMarkdownBlock] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = trimmed.drop(while: { $0 == "#" || $0 == " " })
                blocks.append(.heading(level: max(1, min(level, 6)), text: String(text)))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quoteLines.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if current.hasPrefix("- ") || current.hasPrefix("* ") {
                        items.append(String(current.dropFirst(2)))
                        index += 1
                    } else if current.isEmpty {
                        index += 1
                        break
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            var paragraphLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("#") || next.hasPrefix("```") || next.hasPrefix(">") || next.hasPrefix("- ") || next.hasPrefix("* ") || next == "---" {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
        }

        return blocks
    }
}
