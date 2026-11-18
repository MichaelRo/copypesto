// SPDX-License-Identifier: MIT
import Foundation
#if os(iOS)
import UIKit
#endif

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

    #if os(iOS)
    /// What iOS calls this device. Without the user-assigned-device-name entitlement that is the model ("iPhone"),
    /// never the name the person chose.
    @MainActor
    public static func current() -> String {
        UIDevice.current.name
    }
    #endif
}
