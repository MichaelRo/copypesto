// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct AppearanceSettings: View {
    @AppStorage(Setting.appearanceMode) private var appearanceModeRaw: String
    @AppStorage(Setting.accentColorHex) private var accentColorHex: String
    @AppStorage(Setting.appTheme) private var appThemeRaw: String
    @AppStorage(Setting.appThemeDark) private var appThemeDarkRaw: String
    @AppStorage(Setting.appIcon) private var appIconRaw: String
    @AppStorage(Setting.cardSize) private var cardSizeRaw: String
    @AppStorage(Setting.cardWidth) private var cardWidth: Int
    @AppStorage(Setting.shelfPosition) private var shelfPositionRaw: String
    @AppStorage(Setting.shelfSurface) private var shelfSurfaceRaw: String
    @State private var showDarkThemePicker = false
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var cardDimensions: CGSize {
        CardSize.dimensions(sizeRaw: cardSizeRaw, customWidth: cardWidth)
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: {
                let range = CardMetrics.sliderRange
                return min(max(cardDimensions.width, Double(range.lowerBound)), Double(range.upperBound))
            },
            set: { cardWidth = Int($0.rounded()) }
        )
    }

    private var darkThemeEnabled: Binding<Bool> {
        Binding(
            get: { !appThemeDarkRaw.isEmpty },
            set: { appThemeDarkRaw = $0 ? appThemeRaw : "" }
        )
    }

    private var accentName: String {
        switch AccentChoice(stored: accentColorHex) {
        case .brand: String(localized: "Theme (\(AppTheme(stored: appThemeRaw).displayName))")
        case let .preset(preset): preset.displayName
        case .custom: String(localized: "Custom")
        }
    }

    var body: some View {
        settingsForm
            .settingsPaneTop {
                VStack(spacing: 0) {
                    SettingsPaneHeader(
                        symbol: "paintbrush", title: "Appearance",
                        subtitle: Text("Make the shelf yours. The picture below shows what you pick.")
                    )
                    // Outside the scrolling form, so it stays in view while a setting below is changed.
                    SettingsShelfPreview(
                        cardDimensions: cardDimensions, appearance: appearanceMode.wrappedValue,
                        accentHex: accentColorHex, themeRaw: appThemeRaw, darkThemeRaw: appThemeDarkRaw,
                        position: ShelfPosition(stored: shelfPositionRaw)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
    }

    private var settingsForm: some View {
        Form {
            Section("Theme") {
                ThemePicker(theme: $appThemeRaw, accentHex: $accentColorHex, iconRaw: $appIconRaw)
                    .settingsRow("Theme")
                LabeledContent {
                    AppIconPicker(selection: $appIconRaw)
                } label: {
                    Text("App icon")
                        .help("Goes with the theme. Change it on its own any time.")
                }
                .settingsRow("App icon")
            }

            Section("Cards") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Card size")
                    LabelledTickSlider(
                        value: widthBinding,
                        range: Double(CardMetrics.sliderRange.lowerBound)...Double(CardMetrics.sliderRange.upperBound),
                        ticks: CardMetrics.recommendedWidths.map {
                            (Double($0), CardMetrics.recommendedName(forWidth: $0) ?? "")
                        },
                        snapTolerance: 6, accessibilityLabel: "Card size",
                        identifier: AccessibilityID.settingsChoice("cardWidth", "slider")
                    )
                }
                .settingsRow("Card size")
            }

            Section("Shelf") {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Shelf surface")
                            InfoPopoverButton(
                                "Shelf surface",
                                message: reduceTransparency
                                    ? "Reduce Transparency is on in System Settings, so the shelf is solid."
                                    : """
                                    Glass shows a little of your desktop. Solid is plain and the same on every desktop.
                                    """
                            )
                        }
                        PreviewPicker(
                            title: "Shelf surface",
                            options: ShelfSurface.allCases,
                            selection: Binding(
                                get: { reduceTransparency ? .solid : ShelfSurface(stored: shelfSurfaceRaw) },
                                set: { shelfSurfaceRaw = $0.rawValue }
                            ),
                            label: \.title,
                            identifier: { AccessibilityID.settingsChoice("shelfSurface", $0.rawValue) },
                            tileSize: CGSize(width: 78, height: 48),
                            cornerRadius: 9,
                            preview: {
                                ShelfSurfacePreview(surface: $0, themeRaw: appThemeRaw, darkThemeRaw: appThemeDarkRaw)
                            }
                        )
                        .disabled(reduceTransparency)
                    }
                    .settingsRow("Shelf surface")

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Shelf position")
                            InfoPopoverButton(
                                "Shelf position",
                                message: """
                                Bottom rests on the Dock. Top hangs from the menu bar, below the notch if your Mac \
                                has one.
                                """
                            )
                        }
                        PreviewPicker(
                            title: "Shelf position",
                            options: ShelfPosition.allCases,
                            selection: Binding(
                                get: { ShelfPosition(stored: shelfPositionRaw) },
                                set: { shelfPositionRaw = $0.rawValue }
                            ),
                            label: \.title,
                            identifier: { AccessibilityID.settingsChoice("shelfPosition", $0.rawValue) },
                            tileSize: CGSize(width: 78, height: 48),
                            cornerRadius: 9,
                            preview: {
                                ShelfPositionPreview(position: $0, themeRaw: appThemeRaw, darkThemeRaw: appThemeDarkRaw)
                            }
                        )
                    }
                    .settingsRow("Shelf position")
                }
                if reduceTransparency {
                    HStack {
                        Text("Reduce Transparency is on in System Settings, so the shelf is solid.").pestoCaption()
                        Spacer()
                        Button("Open System Settings\u{2026}") { SystemSettingsLink.openDisplayAccessibility() }
                            .buttonStyle(.pestoCapsule(.secondary))
                    }
                }
            }

            Section("Light and dark") {
                HStack(alignment: .center, spacing: 12) {
                    Text("Appearance")
                    Spacer()
                    PreviewPicker(
                        title: "Appearance", options: AppearanceMode.allCases, selection: appearanceMode,
                        label: \.label, identifier: { AccessibilityID.settingsChoice("appearance", $0.rawValue) },
                        tileSize: CGSize(width: 74, height: 46),
                        cornerRadius: 9,
                        preview: {
                            AppearanceModePreview(mode: $0, themeRaw: appThemeRaw, darkThemeRaw: appThemeDarkRaw)
                        }
                    )
                    .fixedSize()
                }
                .settingsRow("Appearance: light, dark or system")

                LabeledContent {
                    AccentSwatches(hex: $accentColorHex, identifier: {
                        AccessibilityID.settingsChoice("accent", $0)
                    })
                } label: {
                    HStack(spacing: 6) {
                        Text("Accent color")
                        Text(accentName)
                            .pestoCaption()
                            .accessibilityIdentifier(AccessibilityID.settingsChoice("accent", "name"))
                    }
                }
                .settingsRow("Accent color")

                HStack(spacing: 8) {
                    Toggle("Use another theme in dark mode", isOn: darkThemeEnabled)
                        .accessibilityIdentifier(AccessibilityID.settingsChoice("themeDark", "toggle"))
                    Spacer()
                    if !appThemeDarkRaw.isEmpty {
                        Button(AppTheme(stored: appThemeDarkRaw).displayName) {
                            showDarkThemePicker.toggle()
                        }
                        .buttonStyle(.pestoCapsule(.secondary))
                        .popover(isPresented: $showDarkThemePicker, arrowEdge: .trailing) {
                            ThemePicker(theme: $appThemeDarkRaw, groupLabel: "Theme for dark mode")
                                .frame(width: 320)
                                .padding(14)
                        }
                    }
                    InfoPopoverButton(
                        "Dark mode theme",
                        message: "Pesto\u{2019}s icon goes with the theme you picked above."
                    )
                }
                .settingsRow("Theme in dark mode")
            }
        }
        .formStyle(.grouped)
        .settingsRowScrolling()
        .onDisappear { AccentColorPanel.shared.close() }
    }
}
