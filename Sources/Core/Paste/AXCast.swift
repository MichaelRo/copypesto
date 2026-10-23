// SPDX-License-Identifier: MIT
import ApplicationServices
import Foundation

/// Casts of what the Accessibility API hands back, checked by Core Foundation type id. An app answers however it likes:
/// a cast that assumes the type is undefined behaviour when it answers with another one.
enum AXCast {
    static func element(_ ref: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    static func value(_ ref: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXValue.self)
    }
}
