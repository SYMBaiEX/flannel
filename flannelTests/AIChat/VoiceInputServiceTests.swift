//
//  VoiceInputServiceTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 7/4/26.
//

import Foundation
import Testing
@testable import flannel

struct VoiceInputServiceTests {
    @Test("Voice transcript fills an empty composer")
    func voiceTranscriptFillsEmptyComposer() {
        #expect(
            VoiceInputComposerFormatter.composedText(
                existingText: "   ",
                transcript: "Draft a local RAG plan"
            ) == "Draft a local RAG plan"
        )
    }

    @Test("Voice transcript appends to existing composer text")
    func voiceTranscriptAppendsToExistingComposerText() {
        #expect(
            VoiceInputComposerFormatter.composedText(
                existingText: "Compare Ollama and LM Studio",
                transcript: "for private code review"
            ) == "Compare Ollama and LM Studio for private code review"
        )

        #expect(
            VoiceInputComposerFormatter.composedText(
                existingText: "Checklist:\n",
                transcript: "Verify providers"
            ) == "Checklist:\nVerify providers"
        )
    }

    @Test("Empty voice transcript preserves composer text")
    func emptyVoiceTranscriptPreservesComposerText() {
        #expect(
            VoiceInputComposerFormatter.composedText(
                existingText: "Keep this draft",
                transcript: "\n \t"
            ) == "Keep this draft"
        )
    }

    @Test("Voice state labels on-device and Apple fallback modes clearly")
    func voiceStateLabelsRecognitionBoundary() {
        #expect(VoiceInputState.listening(onDevice: true).title == "Listening on device")
        #expect(VoiceInputState.listening(onDevice: false).title == "Listening with Apple speech")
        #expect(VoiceInputState.unavailable("No on-device recognizer").detail == "No on-device recognizer")
    }

    @Test("Workspace preferences keep Apple speech fallback off for legacy payloads")
    func workspacePreferencesDefaultAppleSpeechFallbackOff() throws {
        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: Data("{}".utf8))

        #expect(WorkspacePreferences().allowAppleSpeechRecognitionFallback == false)
        #expect(decoded.allowAppleSpeechRecognitionFallback == false)
    }
}
