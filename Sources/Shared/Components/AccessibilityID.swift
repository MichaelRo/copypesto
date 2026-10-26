// SPDX-License-Identifier: MIT

/// Accessibility identifiers shared by the app and the UI-test target (which compiles this file too).
enum AccessibilityID {
    static let overlayPanel = "pesto-overlay"
    static let quickMenuPanel = "pesto-quick-menu"
    static let toast = "pesto-toast"
    static let pinnedPanel = "pesto-pinned"
    static let setUpBackupButton = "set-up-backup"
    static let showRecoveryKeyButton = "show-recovery-key"
    static let authenticationUnavailable = "authentication-unavailable"
    static let applyHeldBackSettings = "apply-held-back-settings"
    static let revealHiddenClip = "reveal-hidden-clip"
    static let shelfAuthenticationPrompt = "shelf-authentication-prompt"
    static let autoBackupToggle = "auto-backup-toggle"
    static let autoBackupNowButton = "auto-backup-now"
    static let backupStatus = "backup-status"
    static let onboardingMoreOptions = "onboarding-more-options"
    static let showWelcomeButton = "show-welcome"
    static let copyDiagnosticsButton = "copy-diagnostics"
    static let onboardingMenuBarToggle = "onboarding-menu-bar"
    static let onboardingDevicesToggle = "onboarding-devices"
    static let onboardingLockToggle = "onboarding-lock"
    static let snippetNameField = "snippet-name"
    static let snippetTextEditor = "snippet-text"
    static let snippetPreview = "snippet-preview"
    static let snippetSaveButton = "snippet-save"
    static let aiResultPasteButton = "ai-result-paste"
    static let aiReadNextPartButton = "ai-read-next-part"
    static let aiCancelPartButton = "ai-cancel-part"
    static let aiTryAgainButton = "ai-try-again"
    static let aiCombineButton = "ai-combine"
    static let editSnippetButton = "snippet-edit"
    static let deleteSnippetButton = "snippet-delete"
    static let deleteSnippetConfirmButton = "snippet-delete-confirm"
    static let resumeBackupButton = "resume-backup"
    static let deleteUnreadableClipsButton = "delete-unreadable-clips"
    static let restoreBackupButton = "restore-backup-button"
    static let backupPassphraseField = "backup-passphrase"
    static let backupRepeatField = "backup-passphrase-repeat"
    static let backupSaveButton = "backup-save"
    static let importPasteButton = "import-paste-button"
    static let importMaccyButton = "import-maccy-button"
    static let importAlfredButton = "import-alfred-button"
    static let importCopyClipButton = "import-copyclip-button"
    static let importPastebotButton = "import-pastebot-button"
    static let importPastePalButton = "import-pastepal-button"
    static let importCleanClipButton = "import-cleanclip-button"
    static let importPasteNowButton = "import-pastenow-button"
    static let importClipyButton = "import-clipy-button"
    static let importFlycutButton = "import-flycut-button"
    static let importUnclutterButton = "import-unclutter-button"
    static let importSnippetsButton = "import-snippets-button"
    static let importOtherFileButton = "import-other-file-button"
    static let otherFileSheet = "other-file-sheet"
    static let otherFileContinueButton = "other-file-continue"
    static let importFromAppMenu = "import-from-app-menu"
    static let importPasteConfirm = "import-paste-confirm"
    static let importOfferBanner = "import-offer-banner"
    static func foundOnThisMacRow(_ source: String) -> String {
        "found-on-this-mac-\(source)"
    }

    static let importOfferImportButton = "import-offer-import"
    static let importOfferDismissButton = "import-offer-dismiss"
    static let importPreviewSheet = "import-preview-sheet"
    static let importPreviewHistoryToggle = "import-preview-history-toggle"
    static let importPreviewExpiring = "import-preview-expiring"
    static let importPreviewCancel = "import-preview-cancel"
    static let settingsWindow = "net.copypesto.pesto.settings"
    static let onboardingWindow = "pesto-onboarding"
    static let aboutWindow = "pesto-about"

    static let accessibilityBanner = "overlay-accessibility-banner"
    static let userErrorBanner = "overlay-user-error-banner"
    static let undoBanner = "overlay-undo-banner"
    static let undoButton = "overlay-undo-button"
    static let storageBanner = "overlay-storage-banner"
    static let shelfEmptyState = "shelf-empty-state"
    static let shelfEmptyStateAction = "shelf-empty-state-action"
    static let card = "clipboard-card"
    static let cardDetailPopover = "card-detail-popover"
    static let pasteAllButton = "action-paste-all"
    static let pasteOneByOneButton = "action-paste-one-by-one"
    static let deleteSelectedButton = "action-delete-selected"
    static let deleteConfirmButton = "delete-confirm"
    static let stackCancelButton = "stack-cancel"
    static let deleteCancelButton = "delete-cancel"

    static let searchButton = "toolbar-search"
    static let newCollectionButton = "toolbar-new-collection"
    static let settingsButton = "toolbar-settings"
    static let floatingWindowButton = "toolbar-floating-window"
    static let searchField = "search-field"
    static let searchClearButton = "search-clear"
    static let searchFieldFrame = "search-field-frame"
    static let askButton = "search-ask"
    static let aiUnavailableNotice = "ai-unavailable-notice"
    static let searchCancelButton = "search-cancel"
    static let collectionNameField = "collection-name-field"
    static let collectionOtherColor = "collection-other-color"

    static func filterChip(_ label: String) -> String {
        "filter-chip-\(label)"
    }

    static func filterGroup(_ caption: String) -> String {
        "filter-group-\(caption)"
    }

    static func appChip(_ bundleID: String) -> String {
        "app-chip-\(bundleID)"
    }

    static func tagChip(_ tag: String) -> String {
        "tag-chip-\(tag)"
    }

    static func collectionChip(_ name: String) -> String {
        "collection-chip-\(name)"
    }

    /// Settings fields
    static let excludedAppField = "settings-excluded-app-field"
    static func settingsChoice(_ setting: String, _ value: String) -> String {
        "settings-choice-\(setting)-\(value)"
    }

    static func settingsSearchResult(_ title: String) -> String {
        "settings-search-result-\(title)"
    }

    static let settingsPreviewShelf = "settings-preview-shelf"
    static let settingsPreviewCard = "settings-preview-card"
    static let clearEverythingButton = "settings-clear-everything"
    static func privacyFact(_ name: String) -> String {
        "settings-privacy-fact-\(name)"
    }

    static func shortcutRecorder(_ id: UInt32) -> String {
        "settings-shortcut-\(id)"
    }

    static func shortcutMenu(_ id: UInt32) -> String {
        "settings-shortcut-menu-\(id)"
    }

    static func addSuggestedCollection(_ id: String) -> String {
        "settings-add-suggested-collection-\(id)"
    }

    static func addSnippetStarter(_ id: String) -> String {
        "settings-add-snippet-starter-\(id)"
    }

    static let snippetNeedsPlaceholder = "settings-snippet-needs-placeholder"
    static let restoreSettingsToggle = "settings-restore-settings-toggle"
    static let doubleCopyToggle = "settings-double-copy"
    static let addExcludedAppButton = "settings-add-excluded-app"
    static func removePinnedShortcut(_ slot: Int) -> String {
        "settings-remove-pinned-shortcut-\(slot)"
    }

    static func removeExcludedApp(_ bundleID: String) -> String {
        "settings-remove-excluded-\(bundleID)"
    }

    static func allowExclusion(_ bundleID: String) -> String {
        "settings-allow-exclusion-\(bundleID)"
    }

    static func revokeExclusionAllowance(_ bundleID: String) -> String {
        "settings-revoke-exclusion-\(bundleID)"
    }

    static let launchAtLoginToggle = "settings-launch-at-login"
    static let launchAtLoginUnavailable = "settings-launch-at-login-unavailable"

    /// History lock
    static let lockOverlay = "history-lock-overlay"
    static let unlockButton = "history-unlock-button"

    /// Confirmations
    static let clearConfirmDelete = "clear-confirm-delete"
    static let clearConfirmCancel = "clear-confirm-cancel"

    /// Settings
    static func settingsSidebar(_ section: String) -> String {
        "settings-sidebar-\(section)"
    }

    static let onboardingAccessibilityStep = "onboarding-step-accessibility"
    static let onboardingShelfStep = "onboarding-step-shelf"
    static let onboardingShelfTried = "onboarding-shelf-tried"
    static let onboardingPasteboardNote = "onboarding-pasteboard-note"
    static let onboardingContinueButton = "onboarding-continue"
    static let onboardingSkipAccessibilityButton = "onboarding-skip-accessibility"
    static let onboardingGetStartedButton = "onboarding-get-started"

    /// Shelf suggestions
    static let shelfSuggestionBanner = "shelf-suggestion-banner"
    static let shelfSuggestionAcceptButton = "shelf-suggestion-accept"
    static let shelfSuggestionDeclineButton = "shelf-suggestion-decline"
    static let shelfSuggestionsSettingsToggle = "settings-shelf-suggestions"
    static let resetSuggestionsButton = "settings-reset-suggestions"
}
