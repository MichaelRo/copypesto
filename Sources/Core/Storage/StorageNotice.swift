// SPDX-License-Identifier: MIT

/// The banner that tells a person their history is not being saved, because the store on disk would not open at launch.
public enum StorageNotice {
    public static func message(hasStorage: Bool, isOnDisk: Bool) -> String? {
        guard hasStorage, !isOnDisk else { return nil }
        return "Pesto couldn\u{2019}t open your history, so this session is not saved. Clips are lost when you quit."
    }
}
