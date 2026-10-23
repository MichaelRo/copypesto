// SPDX-License-Identifier: MIT
import Foundation

/// Removes advertising and analytics parameters from a link, and nothing else. Used by the capture rules and by the
/// Paste as… transform, so the two cannot disagree about what a tracking parameter is.
enum TrackingParameters {
    /// `ref` is not here: it is a branch or tag in a GitHub link, and stripping it changes the page.
    private static let keys: Set = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "gclsrc", "mc_eid", "mc_cid",
        "referrer", "igshid", "s_kwcid", "msclkid", "twclid",
        "_hsenc", "_hsmi", "hsCtaTracking"
    ]

    static func removed(from text: String) -> String {
        guard var components = URLComponents(string: text), components.host != nil else { return text }
        // The percent-encoded form is filtered as-is: `queryItems` decodes, and re-encoding turns `%2B` into `+`.
        guard let items = components.percentEncodedQueryItems else { return text }
        let filtered = items.filter { item in
            !keys.contains(item.name.removingPercentEncoding ?? item.name)
        }
        guard filtered.count != items.count else { return text }
        components.percentEncodedQueryItems = filtered.isEmpty ? nil : filtered
        return components.string ?? text
    }
}
