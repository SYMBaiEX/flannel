//
//  MessageContentViews.swift
//  flannel
//
//  Created by OpenAI Codex on 6/30/26.
//

import AppKit
import SwiftUI

struct MarkdownMessageBody: View {
    var text: String

    private var blocks: [MessageContentBlock] {
        MessageContentBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .markdown(let value):
                    MarkdownText(value)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MarkdownText: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CodeBlockView: View {
    var language: String?
    var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(languageLabel, systemImage: "curlybraces")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                MessageCodeCopyButton(code: code)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.35))

            ScrollView(.horizontal, showsIndicators: true) {
                HighlightedCodeText(language: language, code: code)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var languageLabel: String {
        let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Code" : trimmed
    }
}

private struct MessageCodeCopyButton: View {
    var code: String

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(code, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .contentShape(Rectangle())
        .help("Copy code")
        .accessibilityLabel("Copy code")
    }
}

private struct HighlightedCodeText: View {
    var language: String?
    var code: String

    private var text: Text {
        CodeSyntaxHighlighter.segments(in: code, language: language).reduce(Text("")) { partial, segment in
            partial + Text(segment.text).foregroundStyle(color(for: segment.kind))
        }
    }

    var body: some View {
        text
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
    }

    private func color(for kind: CodeSyntaxTokenKind?) -> Color {
        switch kind {
        case .keyword:
            return .purple
        case .stringLiteral:
            return .green
        case .numberLiteral:
            return .orange
        case .comment:
            return .secondary
        case .function:
            return .blue
        case .typeName:
            return .teal
        case nil:
            return .primary
        }
    }
}

private struct MessageContentBlock: Identifiable {
    enum Kind {
        case markdown(String)
        case code(language: String?, code: String)
    }

    var id = UUID()
    var kind: Kind

    static func parse(_ text: String) -> [MessageContentBlock] {
        var blocks: [MessageContentBlock] = []
        var buffer: [String] = []
        var isInCodeBlock = false
        var codeLanguage: String?

        func flushMarkdown() {
            let value = buffer.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(MessageContentBlock(kind: .markdown(value)))
            }
            buffer.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            let value = buffer.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            blocks.append(MessageContentBlock(kind: .code(language: codeLanguage, code: value)))
            buffer.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    flushCode()
                    isInCodeBlock = false
                } else {
                    flushMarkdown()
                    codeLanguage = String(trimmed.dropFirst(3))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    isInCodeBlock = true
                }
            } else {
                buffer.append(line)
            }
        }

        if isInCodeBlock {
            flushCode()
        } else {
            flushMarkdown()
        }

        return blocks.isEmpty ? [MessageContentBlock(kind: .markdown(text))] : blocks
    }
}
