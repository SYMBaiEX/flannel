//
//  CodeSyntaxHighlighter.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated enum CodeSyntaxTokenKind: String, Hashable, Sendable {
    case keyword
    case stringLiteral
    case numberLiteral
    case comment
    case function
    case typeName
}

nonisolated struct CodeSyntaxSegment: Hashable, Identifiable, Sendable {
    var id: Int { offset }

    var offset: Int
    var text: String
    var kind: CodeSyntaxTokenKind?
}

nonisolated enum CodeSyntaxHighlighter {
    static func segments(in code: String, language: String?) -> [CodeSyntaxSegment] {
        guard !code.isEmpty else { return [] }

        let grammar = CodeSyntaxGrammar(language: language)
        let scanner = CodeSyntaxScanner(code: code, grammar: grammar)
        return scanner.scan()
    }
}

nonisolated private struct CodeSyntaxScanner {
    let code: String
    let grammar: CodeSyntaxGrammar
    private let characters: [Character]

    init(code: String, grammar: CodeSyntaxGrammar) {
        self.code = code
        self.grammar = grammar
        characters = Array(code)
    }

    func scan() -> [CodeSyntaxSegment] {
        var segments: [CodeSyntaxSegment] = []
        var plainStart = 0
        var index = 0

        func emitPlain(upTo offset: Int) {
            guard offset > plainStart else { return }
            segments.append(segment(from: plainStart, to: offset, kind: nil))
            plainStart = offset
        }

        func emitToken(from start: Int, to end: Int, kind: CodeSyntaxTokenKind) {
            guard end > start else { return }
            emitPlain(upTo: start)
            segments.append(segment(from: start, to: end, kind: kind))
            plainStart = end
        }

        while index < characters.count {
            if let end = lineCommentEnd(startingAt: index) {
                emitToken(from: index, to: end, kind: .comment)
                index = end
                continue
            }

            if let end = blockCommentEnd(startingAt: index) {
                emitToken(from: index, to: end, kind: .comment)
                index = end
                continue
            }

            if grammar.stringDelimiters.contains(characters[index]) {
                let end = stringLiteralEnd(startingAt: index, delimiter: characters[index])
                emitToken(from: index, to: end, kind: .stringLiteral)
                index = end
                continue
            }

            if isNumberStart(at: index) {
                let end = numberLiteralEnd(startingAt: index)
                emitToken(from: index, to: end, kind: .numberLiteral)
                index = end
                continue
            }

            if isIdentifierStart(characters[index]) {
                let end = identifierEnd(startingAt: index)
                let identifier = String(characters[index..<end])

                if grammar.keywords.contains(identifier) {
                    emitToken(from: index, to: end, kind: .keyword)
                } else if isFunctionName(from: end) {
                    emitToken(from: index, to: end, kind: .function)
                } else if isTypeName(identifier) {
                    emitToken(from: index, to: end, kind: .typeName)
                }

                index = end
                continue
            }

            index += 1
        }

        emitPlain(upTo: characters.count)
        return segments
    }

    private func segment(from start: Int, to end: Int, kind: CodeSyntaxTokenKind?) -> CodeSyntaxSegment {
        let lowerBound = code.index(code.startIndex, offsetBy: start)
        let upperBound = code.index(code.startIndex, offsetBy: end)
        return CodeSyntaxSegment(
            offset: start,
            text: String(code[lowerBound..<upperBound]),
            kind: kind
        )
    }

    private func lineCommentEnd(startingAt index: Int) -> Int? {
        for marker in grammar.lineCommentMarkers where matches(marker, at: index) {
            var end = index + marker.count
            while end < characters.count && characters[end] != "\n" {
                end += 1
            }
            return end
        }
        return nil
    }

    private func blockCommentEnd(startingAt index: Int) -> Int? {
        guard matches(["/", "*"], at: index) else { return nil }

        var end = index + 2
        while end + 1 < characters.count {
            if characters[end] == "*", characters[end + 1] == "/" {
                return end + 2
            }
            end += 1
        }
        return characters.count
    }

    private func stringLiteralEnd(startingAt index: Int, delimiter: Character) -> Int {
        var end = index + 1
        var isEscaped = false

        while end < characters.count {
            let character = characters[end]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == delimiter {
                return end + 1
            } else if character == "\n", delimiter != "`" {
                return end
            }
            end += 1
        }

        return end
    }

    private func isNumberStart(at index: Int) -> Bool {
        guard characters[index].isNumber else { return false }
        if index > 0, isIdentifierPart(characters[index - 1]) {
            return false
        }
        return true
    }

    private func numberLiteralEnd(startingAt index: Int) -> Int {
        var end = index
        while end < characters.count {
            let character = characters[end]
            if character.isNumber || character == "." || character == "_" || character == "x" || character == "X" {
                end += 1
            } else {
                break
            }
        }
        return end
    }

    private func identifierEnd(startingAt index: Int) -> Int {
        var end = index + 1
        while end < characters.count, isIdentifierPart(characters[end]) {
            end += 1
        }
        return end
    }

    private func isFunctionName(from end: Int) -> Bool {
        guard !grammar.isDataLanguage else { return false }

        var index = end
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
        return index < characters.count && characters[index] == "("
    }

    private func isTypeName(_ identifier: String) -> Bool {
        guard grammar.highlightsTypeNames,
              let first = identifier.unicodeScalars.first else {
            return false
        }
        return CharacterSet.uppercaseLetters.contains(first)
    }

    private func matches(_ marker: [Character], at index: Int) -> Bool {
        guard index + marker.count <= characters.count else { return false }
        for offset in marker.indices where characters[index + offset] != marker[offset] {
            return false
        }
        return true
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private func isIdentifierPart(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

nonisolated private struct CodeSyntaxGrammar {
    var language: String
    var keywords: Set<String>
    var stringDelimiters: Set<Character>
    var lineCommentMarkers: [[Character]]
    var isDataLanguage: Bool
    var highlightsTypeNames: Bool

    init(language: String?) {
        self.language = Self.normalizedLanguage(language)
        keywords = Self.keywords(for: self.language)
        stringDelimiters = Self.stringDelimiters(for: self.language)
        lineCommentMarkers = Self.lineCommentMarkers(for: self.language)
        isDataLanguage = Self.dataLanguages.contains(self.language)
        highlightsTypeNames = !isDataLanguage && self.language != "sh" && self.language != "bash"
    }

    private static let dataLanguages: Set<String> = ["json", "yaml", "yml", "toml"]

    private static func normalizedLanguage(_ value: String?) -> String {
        let raw = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let firstToken = raw.split { !$0.isLetter && !$0.isNumber && $0 != "#" && $0 != "+" }.first.map(String.init) ?? raw

        switch firstToken {
        case "js", "jsx", "javascript":
            return "javascript"
        case "ts", "tsx", "typescript":
            return "typescript"
        case "shell", "zsh", "fish", "sh":
            return "sh"
        case "py":
            return "python"
        case "rb":
            return "ruby"
        case "rs":
            return "rust"
        case "golang":
            return "go"
        default:
            return firstToken
        }
    }

    private static func stringDelimiters(for language: String) -> Set<Character> {
        switch language {
        case "javascript", "typescript", "sh", "bash":
            return ["\"", "'", "`"]
        default:
            return ["\"", "'"]
        }
    }

    private static func lineCommentMarkers(for language: String) -> [[Character]] {
        switch language {
        case "python", "ruby", "sh", "bash", "yaml", "yml", "toml":
            return [["#"]]
        case "sql":
            return [["-", "-"]]
        default:
            return [["/", "/"]]
        }
    }

    private static func keywords(for language: String) -> Set<String> {
        switch language {
        case "swift":
            return [
                "actor", "as", "async", "await", "case", "catch", "class", "continue", "default",
                "defer", "do", "else", "enum", "extension", "false", "for", "func", "guard",
                "if", "import", "in", "init", "let", "nil", "private", "protocol", "public",
                "return", "self", "static", "struct", "switch", "throw", "throws", "true",
                "try", "var", "where", "while"
            ]
        case "javascript", "typescript":
            return [
                "async", "await", "break", "case", "catch", "class", "const", "continue", "default",
                "else", "export", "extends", "false", "for", "from", "function", "if", "import",
                "interface", "let", "new", "null", "return", "switch", "throw", "true", "try",
                "type", "undefined", "var", "while"
            ]
        case "python":
            return [
                "and", "as", "async", "await", "break", "class", "continue", "def", "elif",
                "else", "except", "False", "finally", "for", "from", "if", "import", "in",
                "is", "lambda", "None", "not", "or", "pass", "raise", "return", "True",
                "try", "while", "with", "yield"
            ]
        case "rust":
            return [
                "async", "await", "break", "const", "continue", "crate", "else", "enum", "false",
                "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut",
                "pub", "ref", "return", "self", "Self", "static", "struct", "trait", "true",
                "type", "use", "where", "while"
            ]
        case "go":
            return [
                "break", "case", "chan", "const", "continue", "default", "defer", "else",
                "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
                "map", "nil", "package", "range", "return", "select", "struct", "switch",
                "type", "var"
            ]
        case "json":
            return ["true", "false", "null"]
        case "sql":
            return [
                "and", "as", "by", "case", "create", "delete", "desc", "distinct", "drop",
                "else", "from", "group", "having", "in", "insert", "into", "is", "join",
                "left", "limit", "not", "null", "on", "or", "order", "right", "select",
                "then", "update", "values", "when", "where"
            ]
        case "sh", "bash":
            return [
                "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function",
                "if", "in", "local", "then", "while"
            ]
        default:
            return [
                "async", "await", "case", "class", "const", "else", "enum", "false", "for",
                "func", "function", "if", "import", "let", "nil", "null", "return", "struct",
                "true", "type", "var", "while"
            ]
        }
    }
}
