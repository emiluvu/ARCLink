//
//  TranslationSnippetView.swift
//  ARCLink
//
//  Created by Rayan Ezaz on 4/29/26.
//

import SwiftUI

struct TranslationSnippetView: View {
    let original: String
    let translated: String
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(Color.arcAccentOrange)
                Text("ARCLink Translation")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Divider()

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                if !original.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("English", systemImage: "globe")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(original)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }

                if !translated.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Español", systemImage: "globe")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.arcAccentOrange)
                        Text(translated)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 4)
    }
}
