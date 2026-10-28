// SPDX-License-Identifier: MIT
import Foundation

/// Every preference and every piece of small state Pesto keeps in `UserDefaults`, with its default. A key is named
/// here once: `@AppStorage(Setting.cardSize)` in a view, `AppDefaults.store.value(for: Setting.cardSize)` anywhere
/// else. `SettingKeyTests` fails on a duplicate name, and `SettingsRegistryTests` on a raw key in the sources.
///
/// Keys that belong to one policy type and travel with its own typed store (`PrivacyStats`, `ExclusionAllowances`,
/// `AutoBackupSettings`) stay with that type; the ones its Settings pane binds are listed here by name.
public enum Setting {
    // MARK: Appearance

    public static let appearanceMode = SettingKey("appearanceMode", default: "system")
    public static let accentColorHex = SettingKey("accentColorHex", default: AccentChoice.defaultStored)
    public static let appTheme = SettingKey("appTheme", default: AppTheme.basil.rawValue)
    /// The theme for dark appearance; empty means the same one as `appTheme`.
    public static let appThemeDark = SettingKey("appThemeDark", default: "")
    public static let appIcon = SettingKey("appIcon", default: AppIconChoice.basil.rawValue)
    public static let cardSize = SettingKey("cardSize", default: "large")
    public static let cardWidth = SettingKey("cardWidth", default: 0)
    public static let shelfPosition = SettingKey("shelfPosition", default: ShelfPosition.bottom.rawValue)

    // MARK: History

    public static let retentionDays = SettingKey("retentionDays", default: 30)
    public static let retentionMaxItems = SettingKey("retentionMaxItems", default: 5000)
    public static let clearOnScreenLock = SettingKey("clearOnScreenLock", default: false)
    public static let clearOnQuit = SettingKey("clearOnQuit", default: false)

    // MARK: Capture

    public static let ruleStripTracking = SettingKey("ruleStripTracking", default: true)
    public static let ruleTrimWhitespace = SettingKey("ruleTrimWhitespace", default: false)
    public static let ruleNormalizeLineEndings = SettingKey("ruleNormalizeLineEndings", default: true)
    public static let ruleRemoveDuplicateSpaces = SettingKey("ruleRemoveDuplicateSpaces", default: false)
    public static let doubleCopyAppend = SettingKey("doubleCopyAppendEnabled", default: false)
    public static let additionalExcludedBundleIDs = SettingKey("additionalExcludedBundleIDs", default: "")

    // MARK: Privacy

    public static let nsfwMode = SettingKey("nsfwMode", default: "blur")
    public static let keepsRemoteCopies = SettingKey("keepsRemoteCopies", default: false)
    public static let opensQuickMenuAtCursor = SettingKey("opensQuickMenuAtCursor", default: false)
    public static let screenSharingPrivacy = SettingKey("screenSharingPrivacy", default: false)
    public static let biometricLockEnabled = SettingKey("biometricLockEnabled", default: false)
    public static let biometricLockTimeoutMinutes = SettingKey(
        "biometricLockTimeoutMinutes", default: 5
    )
    public static let authenticationGraceMinutes = SettingKey(
        "authenticationGraceMinutes", default: 5
    )
    public static let linkPreviews = SettingKey(LinkPreviewPolicy.defaultsKey, default: false)
    public static let appleIntelligenceEnabled = SettingKey("appleIntelligenceEnabled", default: true)

    // MARK: General

    public static let pinnedWindowAutoPaste = SettingKey("pinnedWindowAutoPaste", default: true)
    public static let pictureSaveFolder = SettingKey("pictureSaveFolder", default: "")
    public static let soundEffects = SettingKey(SoundEffectPolicy.defaultsKey, default: false)
    public static let searchHistory = SettingKey("searchHistory", default: "")
    public static let hasOnboarded = SettingKey("hasOnboarded", default: false)
    public static let showMenuBarIcon = SettingKey("showMenuBarIcon", default: true)
    public static let shelfSuggestionsEnabled = SettingKey("shelfSuggestionsEnabled", default: true)
    public static let rememberFillIns = SettingKey("rememberFillIns", default: true)

    // MARK: Shortcuts (key code and modifier mask; a zero mask means the default, or none for the optional ones)

    public static let overlayHotkeyKeyCode = SettingKey("overlayHotkeyKeyCode", default: 0)
    public static let overlayHotkeyModifiers = SettingKey("overlayHotkeyModifiers", default: 0)
    public static let quickPasteHotkeyKeyCode = SettingKey("quickPasteHotkeyKeyCode", default: 0)
    public static let quickPasteHotkeyModifiers = SettingKey("quickPasteHotkeyModifiers", default: 0)
    public static let pastePlainHotkeyKeyCode = SettingKey("pastePlainHotkeyKeyCode", default: 0)
    public static let pastePlainHotkeyModifiers = SettingKey("pastePlainHotkeyModifiers", default: 0)
    public static let togglePinnedWindowHotkeyKeyCode = SettingKey("togglePinnedWindowHotkeyKeyCode", default: 0)
    public static let togglePinnedWindowHotkeyModifiers = SettingKey("togglePinnedWindowHotkeyModifiers", default: 0)
    public static let toggleCaptureHotkeyKeyCode = SettingKey("toggleCaptureHotkeyKeyCode", default: 0)
    public static let toggleCaptureHotkeyModifiers = SettingKey("toggleCaptureHotkeyModifiers", default: 0)
    public static let toggleClipContentsHotkeyKeyCode = SettingKey("toggleClipContentsHotkeyKeyCode", default: 0)
    public static let toggleClipContentsHotkeyModifiers = SettingKey("toggleClipContentsHotkeyModifiers", default: 0)

    // MARK: State this Mac keeps about itself (never exported)

    public static let settingsWindowFrame = SettingKey("settingsWindowFrame", default: "")
    /// The pane Settings was last on, so it opens there again.
    /// The person chose "Continue Without Auto-Paste" in setup, so an update does not ask for Accessibility again.
    public static let declinedAutoPaste = SettingKey("declinedAutoPaste", default: false)
    public static let lastSettingsPane = SettingKey("lastSettingsPane", default: "General")
    public static let pinnedWindowFrame = SettingKey("pinnedWindowFrame", default: "")
    public static let samplesSeeded = SettingKey("samplesSeeded", default: false)
    /// Whether the person has been offered, or has answered, the first-launch offer to import another app's history.
    public static let importOffered = SettingKey("importOffered", default: false)
    /// Ids of collection suggestions the person dismissed, one per line.
    /// Ids of snippet suggestions (a starter's id, or a clip's UUID) the person dismissed, one per line.
    public static let dismissedSnippetSuggestions = SettingKey("dismissedSnippetSuggestions", default: "")
    public static let dismissedCollectionSuggestions = SettingKey("dismissedCollectionSuggestions", default: "")
    public static let installPromptSuppressed = SettingKey("installLocationPromptSuppressed", default: false)
    public static let previewEncryptionVersion = SettingKey("previewEncryptionVersion", default: 0)
    public static let metadataSealingVersion = SettingKey("metadataSealingVersion", default: 0)
    public static let embeddingSealingVersion = SettingKey("embeddingSealingVersion", default: 0)
    public static let ciphertextBindingVersion = SettingKey("ciphertextBindingVersion", default: 0)
    public static let classifierVersion = SettingKey("classifierVersion", default: 0)
    public static let clipRepairVersion = SettingKey("clipRepairVersion", default: 0)
    public static let secretMaskVersion = SettingKey("secretMaskVersion", default: 0)
    public static let authenticationWindowMigrated = SettingKey("authenticationWindowMigrated", default: false)
    public static let spotlightIndexRemoved = SettingKey("spotlightIndexRemoved", default: false)
    public static let legacyPreferencesCopied = SettingKey("legacyPreferencesCopied", default: false)
    public static let legacyAIKeysRemoved = SettingKey("legacyAIKeysRemoved", default: false)
    public static let shelfSuggestionsArmedAt = SettingKey("shelfSuggestionsArmedAt", default: 0)
    public static let shelfSuggestionsLastShownAt = SettingKey("shelfSuggestionsLastShownAt", default: 0)
    public static let shelfSuggestionDeclines = SettingKey("shelfSuggestionDeclines", default: 0)
    public static let shelfSuggestionLedger = SettingKey("shelfSuggestionLedger", default: "")

    // MARK: Switches only a UI test sets

    public static let uitestAuthenticationGranted = SettingKey("uitestAuthenticationGranted", default: false)
    public static let uitestAuthenticationUnavailable = SettingKey("uitestAuthenticationUnavailable", default: false)

    /// Every key's name, for the tests that keep the list honest.
    public static let allNames: [String] = [
        appearanceMode.name, accentColorHex.name, appTheme.name, appThemeDark.name, appIcon.name, cardSize.name,
        cardWidth.name, shelfPosition.name,
        retentionDays.name, retentionMaxItems.name, clearOnScreenLock.name, clearOnQuit.name,
        ruleStripTracking.name, ruleTrimWhitespace.name, ruleNormalizeLineEndings.name,
        ruleRemoveDuplicateSpaces.name, doubleCopyAppend.name, additionalExcludedBundleIDs.name,
        nsfwMode.name, keepsRemoteCopies.name, opensQuickMenuAtCursor.name, screenSharingPrivacy.name,
        biometricLockEnabled.name,
        biometricLockTimeoutMinutes.name,
        authenticationGraceMinutes.name, linkPreviews.name,
        appleIntelligenceEnabled.name, pinnedWindowAutoPaste.name, pictureSaveFolder.name, soundEffects.name,
        searchHistory.name,
        hasOnboarded.name, showMenuBarIcon.name, shelfSuggestionsEnabled.name, rememberFillIns.name,
        overlayHotkeyKeyCode.name,
        overlayHotkeyModifiers.name,
        quickPasteHotkeyKeyCode.name,
        quickPasteHotkeyModifiers.name, pastePlainHotkeyKeyCode.name, pastePlainHotkeyModifiers.name,
        togglePinnedWindowHotkeyKeyCode.name, togglePinnedWindowHotkeyModifiers.name,
        toggleCaptureHotkeyKeyCode.name, toggleCaptureHotkeyModifiers.name,
        toggleClipContentsHotkeyKeyCode.name, toggleClipContentsHotkeyModifiers.name,
        settingsWindowFrame.name, lastSettingsPane.name, declinedAutoPaste.name, pinnedWindowFrame.name,
        samplesSeeded.name, importOffered.name,
        dismissedSnippetSuggestions.name,
        dismissedCollectionSuggestions.name,
        installPromptSuppressed.name,
        previewEncryptionVersion.name, metadataSealingVersion.name, embeddingSealingVersion.name,
        ciphertextBindingVersion.name, classifierVersion.name, clipRepairVersion.name, secretMaskVersion.name,
        authenticationWindowMigrated.name, spotlightIndexRemoved.name,
        legacyPreferencesCopied.name,
        legacyAIKeysRemoved.name,
        shelfSuggestionsArmedAt.name,
        shelfSuggestionsLastShownAt.name,
        shelfSuggestionDeclines.name,
        shelfSuggestionLedger.name,
        uitestAuthenticationGranted.name, uitestAuthenticationUnavailable.name
    ]
}
