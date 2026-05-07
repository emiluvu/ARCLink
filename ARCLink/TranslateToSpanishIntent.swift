//
//  TranslateToSpanishIntent.swift
//  ARCLink
//
//  Created by Rayan Ezaz on 4/29/26.
//

import AppIntents
import SwiftUI

private let googleTranslateAPIKey = "AIzaSyANen8vJtfVpeLtgsvz2HJXELF5hj0hrgU"

// MARK: - Google Translate API response model

private struct GoogleTranslateResponse: Decodable {
    struct Data: Decodable {
        struct Translation: Decodable {
            let translatedText: String
        }
        let translations: [Translation]
    }
    let data: Data
}

// MARK: - Errors

private enum TranslationError: Error {
    case invalidInput
    case networkError
    case emptyResult
}

// MARK: - Intent

struct TranslateToSpanishIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate to Spanish"
    static let description = IntentDescription(
        "Speak a phrase in English and hear it read back in Spanish."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Phrase",
        description: "The English phrase to translate",
        requestValueDialog: IntentDialog("What would you like to translate?")
    )
    var phrase: String

    @Parameter(
        title: "Keep Translating",
        description: "Whether to translate another phrase",
        requestValueDialog: IntentDialog("Would you like to translate another phrase? Say yes or no.")
    )
    var keepTranslating: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$phrase) to Spanish")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw $phrase.needsValueError("What would you like to translate?")
        }

        let translated: String
        let errorMessage: String?

        do {
            translated = try await translateToSpanish(trimmed)
            errorMessage = nil
        } catch {
            translated = ""
            errorMessage = "Translation failed. Please check your connection and try again."
        }

        let view = TranslationSnippetView(
            original: trimmed,
            translated: translated,
            errorMessage: errorMessage
        )

        let spokenText = errorMessage ?? translated

        // If keepTranslating hasn't been answered yet, ask Siri to listen for yes/no
        if !keepTranslating {
            throw $keepTranslating.needsValueError(
                "\(spokenText). Would you like to translate another phrase?"
            )
        }

        // If yes, reset and loop back
        phrase = ""
        keepTranslating = false
        throw $phrase.needsValueError("What would you like to translate?")

        // Required return to satisfy opaque return type
        return .result(
            dialog: IntentDialog("Translation complete."),
            view: view
        )
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

        let decoded = try JSONDecoder().decode(GoogleTranslateResponse.self, from: data)

        guard let translatedText = decoded.data.translations.first?.translatedText,
              !translatedText.isEmpty
        else {
            throw TranslationError.emptyResult
        }

        return translatedText
    }
}
