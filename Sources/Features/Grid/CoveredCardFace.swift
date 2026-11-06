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
            .overlay(alignment: .top) { top }
            .overlay { centre }
            .overlay {
                if let ringColor {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ringColor, lineWidth: 1.5)
                }
            }
    }

    private var top: some View {
        HStack {
            if let number = facts.numberLabel {
                Text(number)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 4)
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.6)) }
            }
            Spacer(minLength: 4)
            Text(facts.age)
                .font(.caption2)
                .foregroundStyle(AdaptiveContrast.quiet(contrast))
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
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
