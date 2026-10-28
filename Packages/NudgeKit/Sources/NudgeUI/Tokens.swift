import AppKit
import NudgeCore
import SwiftUI

// Design tokens from the approved mockups and the spec's Design Addendum.

enum Tokens {
    enum Palette {
        static let text = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
        static let secondary = dynamic(light: 0x56565C, dark: 0xB4B4BB)
        static let tertiary = dynamic(light: 0x8E8E93, dark: 0x8E8E93)
        static let hairline = dynamic(light: .black, 0.08, dark: .white, 0.10)
        static let fill = dynamic(light: .black, 0.05, dark: .white, 0.08)
        static let fillHover = dynamic(light: .black, 0.09, dark: .white, 0.14)
        static let fillStrong = dynamic(light: .black, 0.12, dark: .white, 0.18)
        static let segmentOn = dynamic(light: .white, 1, dark: .white, 0.2)
        /// Brand violet, for fills under white text (4.6:1). Stays put in dark mode: the lighter #8F7BFF would drop
        /// white text to 3.3:1. Not `Color.accentColor`, which follows the system accent unless it's Multicolor.
        static let accent = Color(hex: 0x7457FF)
        static let accentPressed = Color(hex: 0x5E41EE)
        /// Brand violet as a glyph color on glass (sparkles, the synced dot).
        static let accentGlyph = dynamic(light: 0x7457FF, dark: 0x8F7BFF)
        static let check = Color(hex: 0x1F9D55)
        static let warning = dynamic(light: 0xA84D07, dark: 0xFFB35C)
        /// Sits between the glass and the pill's content: lifts light glass a little, darkens dark glass so the
        /// tier colors hold contrast on any wallpaper.
        static let glassScrim = dynamic(light: .white, 0.16, dark: .black, 0.30)
        /// Under the hero timer and count in dark mode only.
        static let textShadow = dynamic(light: .clear, 0, dark: .black, 0.45)

        // Settings window is dark glass in both appearances.
        static let settingsText = Color(hex: 0xF5F5F7)
        static let settingsSecondary = Color(hex: 0xB4B4BB)
        static let settingsLabel = Color(hex: 0xC9C9CF)
        static let settingsWindow = Color(hex: 0x18181E).opacity(0.62)
        static let settingsSidebar = Color.white.opacity(0.07)
        static let settingsCard = Color.white.opacity(0.06)
        static let settingsCardEdge = Color.white.opacity(0.09)
        static let settingsField = Color.black.opacity(0.28)
        static let settingsFieldEdge = Color.white.opacity(0.14)
        static let settingsSelected = Color(hex: 0x8F7BFF).opacity(0.24)
        static let tokenChip = Color(hex: 0x8F7BFF).opacity(0.22)
        static let tokenText = Color(hex: 0xC9BFFF)
        static let ok = Color(hex: 0x9FE870)
    }

    enum Tier {
        static func text(_ tier: NudgeCore.Tier) -> Color {
            switch tier {
            case .fresh: dynamic(light: 0x2C2C30, dark: 0xD1D1D6)
            case .amber: dynamic(light: 0x7A3300, dark: 0xFFB35C)
            case .red: dynamic(light: 0x8F1A0E, dark: 0xFF8A80)
            }
        }

        static func dot(_ tier: NudgeCore.Tier) -> Color {
            switch tier {
            case .fresh: Color(hex: 0x8E8E93)
            case .amber: dynamic(light: 0xFF9500, dark: 0xFF9F0A)
            case .red: dynamic(light: 0xFF3B30, dark: 0xFF453A)
            }
        }

        /// Glass tint from concept B; clear for Fresh.
        static func tint(_ tier: NudgeCore.Tier?) -> Color? {
            switch tier {
            case .amber: Color(red: 1, green: 170 / 255, blue: 60 / 255).opacity(0.34)
            case .red: Color(red: 1, green: 80 / 255, blue: 60 / 255).opacity(0.32)
            case .fresh, nil: nil
            }
        }

        /// Faint row tint in the expanded list.
        static func rowTint(_ tier: NudgeCore.Tier) -> Color? {
            switch tier {
            case .amber: Color(red: 1, green: 170 / 255, blue: 60 / 255).opacity(0.14)
            case .red: Color(red: 1, green: 80 / 255, blue: 60 / 255).opacity(0.14)
            case .fresh: nil
            }
        }

        static func chipFill(_ tier: NudgeCore.Tier) -> Color {
            switch tier {
            case .fresh: Palette.fill
            case .amber: Color(red: 1, green: 149 / 255, blue: 0).opacity(0.14)
            case .red: Color(red: 1, green: 59 / 255, blue: 48 / 255).opacity(0.12)
            }
        }
    }

    enum Typo {
        static let pillCount = Font.system(size: 17, weight: .heavy, design: .rounded)
        static let pillTimer = Font.system(size: 21, weight: .heavy, design: .rounded)
        static let pillLabel = Font.system(size: 14, weight: .bold, design: .rounded)
        static let rowTitle = Font.system(size: 15, weight: .bold, design: .rounded)
        static let rowSubtitle = Font.system(size: 12, weight: .medium, design: .rounded)
        static let rowTimer = Font.system(size: 18, weight: .heavy, design: .rounded)
        static let heading = Font.system(size: 15, weight: .bold, design: .rounded)
        static let caption = Font.system(size: 11, weight: .semibold, design: .rounded)
        static let chip = Font.system(size: 12, weight: .bold, design: .rounded)
        static let button = Font.system(size: 12, weight: .semibold, design: .rounded)
        static let menuItem = Font.system(size: 13, weight: .medium, design: .rounded)
        static let menuHint = Font.system(size: 12, weight: .semibold, design: .rounded)
        static let popoverTimer = Font.system(size: 22, weight: .heavy, design: .rounded)
        static let settingsTitle = Font.system(size: 26, weight: .heavy, design: .rounded)
        static let settingsBody = Font.system(size: 13, weight: .medium, design: .rounded)
        static let settingsLabel = Font.system(size: 12, weight: .bold, design: .rounded)
        static let settingsNav = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let code = Font.system(size: 13, design: .monospaced)
        static let codeSmall = Font.system(size: 12, design: .monospaced)
    }

    enum Radius {
        static let pill: CGFloat = 23
        static let panel: CGFloat = 26   // Motion board: capsule radius 23 → card radius 26
        static let dropdown: CGFloat = 18
        static let row: CGFloat = 14
        static let button: CGFloat = 8
        static let chip: CGFloat = 9
        static let menu: CGFloat = 14
        static let menuItem: CGFloat = 9
        static let settingsWindow: CGFloat = 30
        static let settingsSidebar: CGFloat = 22
        static let settingsCard: CGFloat = 20
        static let settingsField: CGFloat = 12
    }

    enum Size {
        static let pillHeight: CGFloat = 46
        static let panelWidth: CGFloat = 420   // room for the subtitle beside the 28pt action cluster
        static let panelMaxHeight: CGFloat = 440
        static let dot: CGFloat = 11
        static let buttonHeight: CGFloat = 26
        static let settingsSidebarWidth: CGFloat = 206
        static let settingsTopInset: CGFloat = 38
    }

    enum Space {
        static let panelInset: CGFloat = 10
        static let rowH: CGFloat = 12
        static let rowV: CGFloat = 6
        static let rowGap: CGFloat = 10
        static let rowLines: CGFloat = 8       // between the timer line and the action line
        static let actionsGap: CGFloat = 6
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

private func dynamic(light: UInt32, dark: UInt32) -> Color {
    dynamic(light: NSColor(Color(hex: light)), dark: NSColor(Color(hex: dark)))
}

private func dynamic(light: NSColor, _ lightAlpha: CGFloat, dark: NSColor, _ darkAlpha: CGFloat) -> Color {
    dynamic(light: light.withAlphaComponent(lightAlpha), dark: dark.withAlphaComponent(darkAlpha))
}

private func dynamic(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}
