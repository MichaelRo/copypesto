// SPDX-License-Identifier: MIT
import CoreGraphics

public enum CardSize: String, CaseIterable, Sendable {
    case compact
    case standard
    case large

    public var label: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    /// The width the person chose with the slider (stored in points, 0 when they have not), or else the named size.
    public static func dimensions(sizeRaw: String?, customWidth: Int) -> CGSize {
        if CardMetrics.widthRange.contains(customWidth) { return CardMetrics.dimensions(width: customWidth) }
        return (sizeRaw.flatMap(CardSize.init(rawValue:)) ?? .large).cardCGSize
    }

    public var width: Int {
        Int(cardCGSize.width)
    }

    public var cardCGSize: CGSize {
        switch self {
        case .compact: CGSize(width: 160, height: 140)
        case .standard: CGSize(width: 180, height: 160)
        case .large: CGSize(width: 200, height: 180)
        }
    }
}
