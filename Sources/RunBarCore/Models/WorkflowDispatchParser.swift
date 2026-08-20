import Foundation

public enum WorkflowDispatchParser {
    public static func parse(_ yaml: String) -> WorkflowDispatchSpec {
        guard let root = MiniYAML.parse(yaml) else {
            return .unsupported
        }
        guard let on = root.value(for: "on") else {
            return .unsupported
        }
        guard let dispatch = dispatchNode(from: on) else {
            return .unsupported
        }
        return WorkflowDispatchSpec(supportsDispatch: true, inputs: inputs(from: dispatch))
    }

    private static func dispatchNode(from on: MiniYAML.Node) -> MiniYAML.Node? {
        if let scalar = on.scalar, scalar == "workflow_dispatch" {
            return .null
        }
        if let sequence = on.sequence {
            let names = sequence.compactMap(\.scalar)
            return names.contains("workflow_dispatch") ? .null : nil
        }
        return on.value(for: "workflow_dispatch")
    }

    private static func inputs(from dispatch: MiniYAML.Node) -> [WorkflowInput] {
        guard let mapping = dispatch.value(for: "inputs")?.mappingPairs else { return [] }
        return mapping.compactMap { key, node in
            guard WorkflowInputName.isValid(key) else { return nil }
            return input(name: key, node: node)
        }
    }

    private static func input(name: String, node: MiniYAML.Node) -> WorkflowInput {
        if node.scalar != nil || node == .null {
            return WorkflowInput(name: name)
        }
        let type = WorkflowInputType.parse(node.value(for: "type")?.scalar)
        let options = node.value(for: "options")?.sequence?.compactMap(\.scalar) ?? []
        return WorkflowInput(
            name: name,
            description: node.value(for: "description")?.scalar,
            type: type,
            required: node.value(for: "required")?.bool ?? false,
            defaultValue: node.value(for: "default")?.stringValue,
            options: options
        )
    }
}

enum MiniYAML {
    enum Node: Equatable, Sendable {
        case scalar(String)
        case mapping([(String, Node)])
        case sequence([Node])
        case null

        static func == (lhs: Node, rhs: Node) -> Bool {
            switch (lhs, rhs) {
            case (.null, .null):
                return true
            case let (.scalar(a), .scalar(b)):
                return a == b
            case let (.sequence(a), .sequence(b)):
                return a == b
            case let (.mapping(a), .mapping(b)):
                return a.map(\.0) == b.map(\.0) && a.map(\.1) == b.map(\.1)
            default:
                return false
            }
        }

        func value(for key: String) -> Node? {
            mappingPairs.first { $0.0 == key }?.1
        }

        var scalar: String? {
            if case let .scalar(value) = self { return value }
            return nil
        }

        var sequence: [Node]? {
            if case let .sequence(value) = self { return value }
            return nil
        }

        var mappingPairs: [(String, Node)] {
            if case let .mapping(value) = self { return value }
            return []
        }

        var bool: Bool? {
            switch scalar?.lowercased() {
            case "true", "yes", "on":
                return true
            case "false", "no", "off":
                return false
            default:
                return nil
            }
        }

        var stringValue: String? {
            if case .null = self { return nil }
            return scalar
        }
    }

    private struct Line {
        var indent: Int
        var content: String
    }

    static func parse(_ text: String) -> Node? {
        let lines = logicalLines(in: text)
        var index = 0
        return parseNode(lines: lines, index: &index, minIndent: 0)
    }

    private static func logicalLines(in text: String) -> [Line] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).compactMap { raw in
            let stripped = stripComment(from: String(raw))
            if stripped.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            if stripped.trimmingCharacters(in: .whitespaces) == "---" { return nil }
            let indent = stripped.prefix { $0 == " " }.count
            let content = String(stripped.dropFirst(indent))
            if content.isEmpty { return nil }
            return Line(indent: indent, content: content)
        }
    }

    private static func stripComment(from line: String) -> String {
        var inSingle = false
        var inDouble = false
        var escaped = false
        for (index, character) in line.enumerated() {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" && inDouble {
                escaped = true
                continue
            }
            if character == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if character == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if character == "#" && !inSingle && !inDouble {
                return String(line.prefix(index))
            }
        }
        return line
    }

    private static func parseNode(lines: [Line], index: inout Int, minIndent: Int) -> Node? {
        guard index < lines.count else { return .null }
        let line = lines[index]
        if line.indent < minIndent { return .null }
        if line.content.hasPrefix("- ") || line.content == "-" {
            return parseSequence(lines: lines, index: &index, indent: line.indent)
        }
        if line.content.hasPrefix("[") || line.content.hasPrefix("{") {
            index += 1
            return parseFlow(line.content)
        }
        if line.content.contains(":") {
            return parseMapping(lines: lines, index: &index, indent: line.indent)
        }
        index += 1
        return parseScalar(line.content)
    }

    private static func parseMapping(lines: [Line], index: inout Int, indent: Int) -> Node {
        var pairs: [(String, Node)] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            if line.indent > indent {
                break
            }
            if line.content.hasPrefix("- ") { break }
            guard let parsed = splitMapping(line.content) else { break }
            index += 1
            let value: Node
            if let inline = parsed.value {
                if inline.hasPrefix("[") || inline.hasPrefix("{") {
                    value = parseFlow(inline) ?? .scalar(inline)
                } else {
                    value = parseScalar(inline)
                }
            } else if index < lines.count, lines[index].indent > indent {
                value = parseNode(lines: lines, index: &index, minIndent: indent + 1) ?? .null
            } else {
                value = .null
            }
            pairs.append((parsed.key, value))
        }
        return .mapping(pairs)
    }

    private static func parseSequence(lines: [Line], index: inout Int, indent: Int) -> Node {
        var items: [Node] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            if line.indent > indent { break }
            guard line.content.hasPrefix("- ") || line.content == "-" else { break }
            let rest = line.content == "-" ? "" : String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            index += 1
            if rest.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    items.append(parseNode(lines: lines, index: &index, minIndent: indent + 1) ?? .null)
                } else {
                    items.append(.null)
                }
            } else if rest.hasPrefix("[") || rest.hasPrefix("{") {
                items.append(parseFlow(rest) ?? parseScalar(rest))
            } else if rest.contains(":"), !rest.hasPrefix("'"), !rest.hasPrefix("\"") {
                var nested = [Line(indent: indent + 2, content: rest)]
                var nestedIndex = 0
                while index < lines.count, lines[index].indent > indent {
                    nested.append(lines[index])
                    index += 1
                }
                items.append(parseMapping(lines: nested, index: &nestedIndex, indent: indent + 2))
            } else {
                items.append(parseScalar(rest))
            }
        }
        return .sequence(items)
    }

    private static func splitMapping(_ content: String) -> (key: String, value: String?)? {
        var inSingle = false
        var inDouble = false
        var escaped = false
        for (index, character) in content.enumerated() {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" && inDouble {
                escaped = true
                continue
            }
            if character == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if character == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if character == ":" && !inSingle && !inDouble {
                let keyRaw = String(content.prefix(index)).trimmingCharacters(in: .whitespaces)
                let valueRaw = String(content.dropFirst(index + 1)).trimmingCharacters(in: .whitespaces)
                let key = unquote(keyRaw)
                guard !key.isEmpty else { return nil }
                return (key, valueRaw.isEmpty ? nil : valueRaw)
            }
        }
        return nil
    }

    private static func parseFlow(_ raw: String) -> Node? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespaces).isEmpty {
                return .sequence([])
            }
            return .sequence(splitFlow(inner).map(parseScalar))
        }
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            let inner = String(trimmed.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespaces).isEmpty {
                return .mapping([])
            }
            let pairs = splitFlow(inner).compactMap { item -> (String, Node)? in
                guard let parsed = splitMapping(item) else { return nil }
                return (parsed.key, parseScalar(parsed.value ?? ""))
            }
            return .mapping(pairs)
        }
        return parseScalar(trimmed)
    }

    private static func splitFlow(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var depth = 0
        for character in raw {
            if character == "'" && !inDouble {
                inSingle.toggle()
                current.append(character)
                continue
            }
            if character == "\"" && !inSingle {
                inDouble.toggle()
                current.append(character)
                continue
            }
            if !inSingle && !inDouble {
                if character == "[" || character == "{" {
                    depth += 1
                } else if character == "]" || character == "}" {
                    depth -= 1
                } else if character == "," && depth == 0 {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    continue
                }
            }
            current.append(character)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }
        return parts
    }

    private static func parseScalar(_ raw: String) -> Node {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "~" || trimmed == "null" || trimmed == "Null" {
            return .null
        }
        return .scalar(unquote(trimmed))
    }

    private static func unquote(_ raw: String) -> String {
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return String(raw.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
        }
        if raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }
        return raw
    }
}
