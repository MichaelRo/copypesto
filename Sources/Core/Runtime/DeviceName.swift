// SPDX-License-Identifier: MIT
import Foundation

public enum DeviceName {
    /// The name the person gave this device. iOS hands an app only the model name, so there the caller's `fallback`
    /// ("iPhone", "iPad") is the name.
    public static func current(fallback: String) -> String {
        #if os(macOS)
        Host.current().localizedName ?? fallback
        #else
        fallback
        #endif
    }
}
