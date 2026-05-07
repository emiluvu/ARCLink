//
//  TranslationView.swift
//  ARCLink
//
//  Created by Rayan Ezaz on 5/6/26.
//

import SwiftUI
import AVFoundation
import Speech

struct TranslationView: View {
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue

    @State private var inputText = ""
    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var isRecording = false
    @State private var errorMessage = ""
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    @State private var synthesizer = AVSpeechSynthesizer()

    private let googleTranslateAPIKey = "AIzaSyANen8vJtfVpeLtgsvz2HJXELF5hj0hrgU"

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    var body: some View {
        List {
            Section("English") {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField(
                        "Type a phrase to translate...",
                        text: $inputText,
                        axis: .vertical
                    )
                    .lineLimit(4)
                    .textInputAutocapitalization(.sentences)

                    if !inputText.isEmpty {
                        Button {
                            inputText = ""
                            translatedText = ""
                            errorMessage = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                            .foregroundStyle(isRecording ? .red : Color.arcAccentOrange)
                        Text(isRecording ? "Tap to stop recording" : "Tap to speak")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isRecording ? .red : Color.arcAccentOrange)
                        if isRecording {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    Task { await translate() }
                } label: {
                    HStack {
                        Spacer()
                        if isTranslating {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(isTranslating ? "Translating..." : "Translate")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
            }

            if !translatedText.isEmpty {
                Section("Español") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(translatedText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Button {
                            speakInSpanish(translatedText)
                        } label: {
                            Label("Speak Again", systemImage: "speaker.wave.2.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.arcAccentOrange)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Translate")
        .listStyle(.insetGrouped)
        .onDisappear {
            stopRecording()
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - Translation

    private func translate() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isTranslating = true
        errorMessage = ""
        translatedText = ""

        do {
            let result = try await translateToSpanish(trimmed)
            translatedText = result
            speakInSpanish(result)
        } catch {
            errorMessage = "Translation failed. Please check your connection and try again."
        }

        isTranslating = false
    }

    private func translateToSpanish(_ text: String) async throws -> String {
        guard let url = URL(string: "https://translation.googleapis.com/language/translate/v2?key=\(googleTranslateAPIKey)") else {
            throw TranslationError.invalidInput
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "q": text,
            "source": "en",
            "target": "es",
            "format": "text"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw TranslationError.networkError
        }

        struct GoogleTranslateResponse: Decodable {
            struct DataBlock: Decodable {
                struct Translation: Decodable {
                    let translatedText: String
                }
                let translations: [Translation]
            }
            let data: DataBlock
        }

        let decoded = try JSONDecoder().decode(GoogleTranslateResponse.self, from: data)

        guard let translatedText = decoded.data.translations.first?.translatedText,
              !translatedText.isEmpty
        else {
            throw TranslationError.emptyResult
        }

        return translatedText
    }

    // MARK: - Speech synthesis

    private func speakInSpanish(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
            ?? AVSpeechSynthesisVoice(language: "es-MX")
            ?? AVSpeechSynthesisVoice(language: "es")
        utterance.rate = 0.48
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    // MARK: - Speech recognition

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    errorMessage = "Microphone access is required. Please enable it in Settings."
                }
                return
            }
            DispatchQueue.main.async {
                do {
                    try beginRecording()
                } catch {
                    errorMessage = "Could not start recording. Please try again."
                }
            }
        }
    }

    private func beginRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result {
                DispatchQueue.main.async {
                    inputText = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    stopRecording()
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    // MARK: - Errors

    private enum TranslationError: Error {
        case invalidInput
        case networkError
        case emptyResult
    }
}
