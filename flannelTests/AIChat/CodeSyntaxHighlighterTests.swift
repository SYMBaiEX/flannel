//
//  CodeSyntaxHighlighterTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/29/26.
//

import Testing
@testable import flannel

struct CodeSyntaxHighlighterTests {
    @Test("Swift highlighting separates keywords, types, functions, strings, numbers, and comments")
    func swiftHighlightingSeparatesTokenKinds() {
        let code = """
        struct Greeter {
            func greet(name: String) -> String {
                return "Hello \\(name)" // friendly
            }
            let count = 42
        }
        """

        let segments = CodeSyntaxHighlighter.segments(in: code, language: "swift")

        #expect(segments.containsToken("struct", .keyword))
        #expect(segments.containsToken("Greeter", .typeName))
        #expect(segments.containsToken("greet", .function))
        #expect(segments.containsToken(#""Hello \(name)""#, .stringLiteral))
        #expect(segments.containsToken("// friendly", .comment))
        #expect(segments.containsToken("42", .numberLiteral))
        #expect(segments.map(\.text).joined() == code)
    }

    @Test("JSON highlighting keeps object keys as strings and literals as typed tokens")
    func jsonHighlightingTreatsKeysAndLiterals() {
        let code = #"{"model":"llama3.1","stream":true,"temperature":0.2,"stop":null}"#

        let segments = CodeSyntaxHighlighter.segments(in: code, language: "json")

        #expect(segments.containsToken(#""model""#, .stringLiteral))
        #expect(segments.containsToken(#""llama3.1""#, .stringLiteral))
        #expect(segments.containsToken("true", .keyword))
        #expect(segments.containsToken("0.2", .numberLiteral))
        #expect(segments.containsToken("null", .keyword))
        #expect(segments.map(\.text).joined() == code)
    }

    @Test("Shell aliases highlight comments, keywords, and quoted strings")
    func shellAliasesHighlightTerminalSnippets() {
        let code = """
        # local model check
        if ollama list; then
          echo "ready"
        fi
        """

        let segments = CodeSyntaxHighlighter.segments(in: code, language: "zsh")

        #expect(segments.containsToken("# local model check", .comment))
        #expect(segments.containsToken("if", .keyword))
        #expect(segments.containsToken("then", .keyword))
        #expect(segments.containsToken(#""ready""#, .stringLiteral))
        #expect(segments.map(\.text).joined() == code)
    }
}

private extension [CodeSyntaxSegment] {
    func containsToken(_ text: String, _ kind: CodeSyntaxTokenKind) -> Bool {
        contains { segment in
            segment.text == text && segment.kind == kind
        }
    }
}
