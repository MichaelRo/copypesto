// SPDX-License-Identifier: MIT

/// One value for each window that hosts a grid, so the shelf and the floating window can each publish what they show
/// without overwriting the other's.
public struct HostValues<Value: Equatable & Sendable>: Sendable {
    private var shelf: Value
    private var pinnedWindow: Value

    public init(_ initial: Value) {
        shelf = initial
        pinnedWindow = initial
    }

    public subscript(host: GridHost) -> Value {
        get { host == .shelf ? shelf : pinnedWindow }
        set { if host == .shelf { shelf = newValue } else { pinnedWindow = newValue } }
    }
}
