// SPDX-License-Identifier: MIT
import Foundation

public struct SnippetStarter: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let text: String
    public let blurb: String
}

/// A few templates to begin with, each using a placeholder so it is a snippet. Plain and professional; the one-line
/// blurb is where Pesto's own voice goes.
public enum SnippetStarters {
    public static let all = [
        SnippetStarter(
            id: "thanks",
            name: "Thank-you reply",
            text: "Hi {{cursor}},\n\nThank you for your message on {{date}}. I will get back to you shortly.\n\nBest,",
            blurb: "A polite answer while you gather the real one."
        ),
        SnippetStarter(
            id: "meeting-notes",
            name: "Meeting notes",
            text: "Meeting notes, {{date}}\n\nAttendees:\n{{cursor}}\n\nDecisions:\n\nNext steps:",
            blurb: "Four headings and a date, so the notes start themselves."
        ),
        SnippetStarter(
            id: "stand-up",
            name: "Stand-up update",
            text: "Stand-up, {{date}}\n\nYesterday:\n{{cursor}}\n\nToday:\n\nBlocked on:",
            blurb: "Yesterday, today and what is in the way."
        ),
        SnippetStarter(
            id: "follow-up",
            name: "Follow-up",
            text: "Hi {{cursor}},\n\nFollowing up on my note from {{date}}. Anything you need from me?\n\nBest,",
            blurb: "A nudge that sounds like you meant it kindly."
        ),
        SnippetStarter(
            id: "timestamp",
            name: "Timestamp",
            text: "{{datetime}}",
            blurb: "Now, written out. Handy for logs and notes."
        )
    ]
}
