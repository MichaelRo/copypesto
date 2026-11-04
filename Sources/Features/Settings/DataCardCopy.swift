// SPDX-License-Identifier: MIT
enum DataCardCopy {
    static let closingNote =
        "Nothing leaves this Mac until you set this up. Clips with secrets stay out unless you choose."

    static let syncSentence =
        "Keeps the Macs where you turn this on matching, so deleting a clip on one deletes it on all; " +
        "sync is not a backup."

    static func backupSentence(isConfigured: Bool) -> String {
        if isConfigured {
            return "One encrypted file, rewritten about an hour after the last change. A backup never changes " +
                "another Mac."
        }
        return "Keeps one encrypted file of your clips, collections, snippets and settings; restore it on any Mac. " +
            "Turning it on asks for a folder and a way to unlock the file first. A backup never changes another Mac."
    }
}
