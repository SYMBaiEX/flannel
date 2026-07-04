//
//  VoiceInputService.swift
//  flannel
//
//  Created by OpenAI Codex on 7/4/26.
//

import AVFoundation
import Foundation
import Observation
import Speech

enum VoiceInputComposerFormatter {
    static func composedText(existingText: String, transcript: String) -> String {
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranscript.isEmpty else { return existingText }

        let cleanExisting = existingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanExisting.isEmpty else { return cleanTranscript }

        if existingText.last?.isWhitespace == true || existingText.last?.isNewline == true {
            return existingText + cleanTranscript
        }

        return existingText + " " + cleanTranscript
    }
}

enum VoiceInputState: Equatable {
    case idle
    case requestingPermission
    case listening(onDevice: Bool)
    case stopping
    case unavailable(String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .requestingPermission, .listening, .stopping:
            true
        case .idle, .unavailable, .failed:
            false
        }
    }

    var isListening: Bool {
        if case .listening = self {
            return true
        }
        return false
    }

    var systemImage: String {
        switch self {
        case .idle:
            "mic"
        case .requestingPermission:
            "mic.badge.plus"
        case .listening:
            "waveform"
        case .stopping:
            "mic.slash"
        case .unavailable:
            "mic.badge.xmark"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .idle:
            "Voice input idle"
        case .requestingPermission:
            "Requesting voice access"
        case .listening(let onDevice):
            onDevice ? "Listening on device" : "Listening with Apple speech"
        case .stopping:
            "Stopping voice input"
        case .unavailable:
            "Voice input unavailable"
        case .failed:
            "Voice input failed"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "Start dictation from the composer."
        case .requestingPermission:
            "macOS may ask for Speech Recognition and microphone access."
        case .listening(let onDevice):
            onDevice
                ? "Speech is being recognized on this Mac and inserted into the composer."
                : "Speech may be processed by Apple's speech service because remote fallback is enabled."
        case .stopping:
            "Finishing the current dictation draft."
        case .unavailable(let message), .failed(let message):
            message
        }
    }
}

@MainActor
@Observable
final class VoiceInputSession {
    var state: VoiceInputState = .idle
    var transcript = ""

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var inputTapInstalled = false
    @ObservationIgnored private var activeSessionID: UUID?

    var isActive: Bool { state.isActive }
    var isListening: Bool { state.isListening }

    func toggle(localeIdentifier: String, allowsAppleSpeechFallback: Bool) {
        if isActive {
            stop()
        } else {
            start(localeIdentifier: localeIdentifier, allowsAppleSpeechFallback: allowsAppleSpeechFallback)
        }
    }

    func start(localeIdentifier: String, allowsAppleSpeechFallback: Bool) {
        guard !isActive else { return }

        let sessionID = UUID()
        activeSessionID = sessionID
        transcript = ""
        state = .requestingPermission

        Task { @MainActor in
            await beginRecognition(
                sessionID: sessionID,
                localeIdentifier: localeIdentifier,
                allowsAppleSpeechFallback: allowsAppleSpeechFallback
            )
        }
    }

    func stop() {
        guard isActive else { return }

        state = .stopping
        activeSessionID = nil
        recognitionRequest?.endAudio()
        teardownAudio(cancelRecognition: true)
        state = .idle
    }

    func clearStatus() {
        switch state {
        case .failed, .unavailable:
            state = .idle
            transcript = ""
        case .idle, .requestingPermission, .listening, .stopping:
            break
        }
    }

    private func beginRecognition(
        sessionID: UUID,
        localeIdentifier: String,
        allowsAppleSpeechFallback: Bool
    ) async {
        let speechStatus = await requestSpeechAuthorization()
        guard isCurrentSession(sessionID) else { return }
        guard speechStatus == .authorized else {
            state = .unavailable(speechAuthorizationMessage(for: speechStatus))
            activeSessionID = nil
            return
        }

        guard await requestMicrophoneAuthorization() else {
            guard isCurrentSession(sessionID) else { return }
            state = .unavailable("Microphone access is required before Flannel can capture dictation.")
            activeSessionID = nil
            return
        }
        guard isCurrentSession(sessionID) else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            state = .unavailable("Speech recognition is not available for \(localeIdentifier).")
            activeSessionID = nil
            return
        }

        guard recognizer.isAvailable else {
            state = .unavailable("Apple speech recognition is not currently available for \(localeIdentifier).")
            activeSessionID = nil
            return
        }

        let canUseOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        guard allowsAppleSpeechFallback || canUseOnDeviceRecognition else {
            state = .unavailable(
                "On-device speech recognition is not available for \(localeIdentifier). Choose another language or disable local-only mode and allow Apple speech fallback in Settings."
            )
            activeSessionID = nil
            return
        }

        do {
            try startAudioRecognition(
                recognizer: recognizer,
                requiresOnDeviceRecognition: !allowsAppleSpeechFallback
            )
        } catch {
            teardownAudio(cancelRecognition: true)
            state = .failed(error.localizedDescription)
            activeSessionID = nil
        }
    }

    private func startAudioRecognition(
        recognizer: SFSpeechRecognizer,
        requiresOnDeviceRecognition: Bool
    ) throws {
        teardownAudio(cancelRecognition: true)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        inputTapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        recognitionRequest = request
        state = .listening(onDevice: requiresOnDeviceRecognition)
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard activeSessionID != nil else { return }

        if let result {
            transcript = result.bestTranscription.formattedString
        }

        if let error {
            teardownAudio(cancelRecognition: false)
            state = .failed(error.localizedDescription)
            activeSessionID = nil
            return
        }

        if result?.isFinal == true {
            teardownAudio(cancelRecognition: false)
            state = .idle
            activeSessionID = nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    private func teardownAudio(cancelRecognition: Bool) {
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
        }

        if inputTapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if cancelRecognition {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        audioEngine = nil
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else { return currentStatus }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private func speechAuthorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            "Speech recognition was denied. Enable it in System Settings to use voice input."
        case .restricted:
            "Speech recognition is restricted on this Mac."
        case .notDetermined:
            "Speech recognition permission has not been granted yet."
        case .authorized:
            "Speech recognition is available."
        @unknown default:
            "Speech recognition is unavailable on this Mac."
        }
    }
}
