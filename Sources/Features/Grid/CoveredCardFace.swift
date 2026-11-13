// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The cover over a card hidden for a screen share. It takes `CoverFacts` and nothing else, so no other fact about the
/// clip can be drawn here (ADR 0028).
struct CoveredCardFace: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let facts: CoverFacts
    let cornerRadius: CGFloat
    /// The accent while the card is focused or part of the selection, so the cover does not hide the ring under it.
    let ringColor: Color?
    /// Why the card is covered, when it is not a screen share ("Sensitive content" for the content filter).
    var note: String?
    let show: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.opaqueSurface)
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).adaptiveMaterialFill() }
            .overlay(alignment: .bottomLeading) { foot }
            .overlay { centre }
            .overlay {
                if let ringColor {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ringColor, lineWidth: 1.5)
                }
            }
    }

    /// The number and the age, at the foot where every other card keeps its line of facts (ADR 0044). Never the app:
    /// ADR 0028 allows the cover three facts.
    private var foot: some View {
        HStack(spacing: 6) {
            if let number = facts.numberLabel {
                Keycap(symbol: number, size: .compact)
            }
            Text(facts.age)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AdaptiveContrast.quiet(contrast))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var centre: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash.fill")
                .font(.title)
            Text(facts.kind)
                .font(.caption2.weight(.medium))
            if let note {
                Text(note).font(.caption2)
            }
            Button(action: show) {
                Text("Show")
                    .padding(.horizontal, 10)
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pestoLink)
            .font(.caption2)
            .help("Show this clip. Return or a double click pastes it without showing it.")
        }
        .pestoQuiet()
    }
}
