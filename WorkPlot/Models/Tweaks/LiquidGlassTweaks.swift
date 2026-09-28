import Foundation

/// Liquid Glass category tweaks.
///
/// Ported from the GoldenNugget-mobile reference
/// (`Nugget/Core/TweakCatalog.swift`, `section: .liquidGlass` specs, plus the
/// `.springboard`-section "Hide Search Button on Home Screen" spec).
///
/// Unlike the rest of the catalog these do NOT touch MobileGestalt's
/// CacheExtra — they write plain booleans into `.GlobalPreferences.plist`
/// and `com.apple.SpringBoard.plist` (see `PlistModification`), applied by
/// `GestaltStore` through the same probe + bad_query lease + verified
/// in-place write that `SpringBoardPlist` uses. Every tweak here needs a
/// respring to take effect; disabling a tweak removes its key again.
enum LiquidGlassTweaks {
    static let all: [Tweak] = [
        Tweak(
            id: "lg-solarium-fallback",
            title: "Solarium Fallback",
            subtitle: "Force the older Solarium rendering path. Respring to apply.",
            category: .liquidGlass,
            symbol: "arrow.counterclockwise",
            isRisky: false,
            notes: "Only offered on iOS 26.5 – 26.6.2.",
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SolariumForceFallback",
                                  value: .bool(true))
            ],
            minIOS: "26.5",
            maxIOS: "26.6.2",
            modifications: [],
        ),
        Tweak(
            id: "lg-ignore-build-check",
            title: "Ignore App Build Check",
            subtitle: "Ignore the linked-on SDK version check for Solarium. Respring to apply.",
            category: .liquidGlass,
            symbol: "checkmark.seal.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck",
                                  value: .bool(true))
            ],
            modifications: [],
        ),
        Tweak(
            id: "lg-lock-screen-glass",
            title: "Disable Liquid Glass on Lock Screen",
            subtitle: "Keep the old solid Lock Screen look. Respring to apply.",
            category: .liquidGlass,
            symbol: "lock.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisallowGlassLockScreen",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
        // SpringBoard domain (ported from the reference's .springboard
        // "Hide Search Button on Home Screen" spec).
        Tweak(
            id: "lg-hide-search-button",
            title: "Disable Search Button on Home Screen",
            subtitle: "Remove the search button below the Home Screen icons. Respring to apply.",
            category: .liquidGlass,
            symbol: "magnifyingglass",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .springBoard,
                                  key: "SBHomeScreenShowsSearchAffordance",
                                  value: .bool(false))
            ],
            modifications: [],
        ),
        Tweak(
            id: "lg-glass-buttons",
            title: "Disallow Glass Buttons",
            subtitle: "Keep the old solid button style. Respring to apply.",
            category: .liquidGlass,
            symbol: "square.on.square",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisallowGlassButtons",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-specular-everywhere",
            title: "Disable Specular Everywhere",
            subtitle: "Remove the glossy glass highlight from all Liquid Glass surfaces. Respring to apply.",
            category: .liquidGlass,
            symbol: "sparkles",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisableSpecularEverywhere",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-clock",
            title: "Disable Liquid Glass Clock",
            subtitle: "Render the Lock Screen clock in the old solid style. Respring to apply.",
            category: .liquidGlass,
            symbol: "clock.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisallowGlassTime",
                                  value: .bool(true))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-dock",
            title: "Disable Liquid Glass Dock",
            subtitle: "Render the Home Screen dock in the old solid style. Respring to apply.",
            category: .liquidGlass,
            symbol: "dock.rectangle",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisableGlassDock",
                                  value: .bool(true))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-widget-specular",
            title: "Disable Widget Specular",
            subtitle: "Remove the specular highlight from Home Screen widgets. Respring to apply.",
            category: .liquidGlass,
            symbol: "square.grid.2x2.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisableWidgetSpecular",
                                  value: .bool(true))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-dock-specular",
            title: "Disable Dock Specular",
            subtitle: "Remove the specular highlight from the Home Screen dock. Respring to apply.",
            category: .liquidGlass,
            symbol: "tray.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisableDockSpecular",
                                  value: .bool(true))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-folder-specular",
            title: "Disable Folder Specular",
            subtitle: "Remove the specular highlight from Home Screen folders. Respring to apply.",
            category: .liquidGlass,
            symbol: "folder.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisableFolderSpecular",
                                  value: .bool(true))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-outer-refraction",
            title: "Disable Outer Refraction",
            subtitle: "Disable the liquid bending of content at the glass edge. Respring to apply.",
            category: .liquidGlass,
            symbol: "drop.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SolariumDisableOuterRefraction",
                                  value: .bool(true))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        // INVERTED: the underlying key is SolariumAllowHDR — turning this
        // tweak ON writes false (HDR off). The subtitle says so explicitly.
        Tweak(
            id: "lg-solarium-hdr",
            title: "Disable Solarium HDR",
            subtitle: "ON writes SolariumAllowHDR = false (HDR off). Can fix washed-out Liquid Glass areas. Respring to apply.",
            category: .liquidGlass,
            symbol: "sun.max.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SolariumAllowHDR",
                                  value: .bool(false))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-specular-motion",
            title: "Disable Specular Motion",
            subtitle: "Stop the moving light reflection on the Lock Screen. Respring to apply.",
            category: .liquidGlass,
            symbol: "wand.and.stars",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SBDisableSpecularEverywhereUsingLSSAssertion",
                                  value: .bool(true))
            ],
            minIOS: "26.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-solarium-intelligence",
            title: "Force Solarium Intelligence",
            subtitle: "Force the experimental adaptive Solarium rendering features. Respring to apply.",
            category: .liquidGlass,
            symbol: "brain",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SolariumForceIntelligence",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-enhanced-speculars",
            title: "Force Enhanced Speculars",
            subtitle: "Enable the enhanced specular rendering pass. Respring to apply.",
            category: .liquidGlass,
            symbol: "sparkles",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "SolariumForceEnhancedSpeculars",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-ui-solarium-fallback",
            title: "UI Solarium Fallback",
            subtitle: "Force UIKit to use the fallback Solarium path. Respring to apply.",
            category: .liquidGlass,
            symbol: "arrow.uturn.left",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "UISolariumForceFallback",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-ignore-hardware-check",
            title: "Ignore Solarium Hardware Check",
            subtitle: "Enable Liquid Glass effects on officially unsupported devices. Respring to apply.",
            category: .liquidGlass,
            symbol: "cpu.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "com.apple.SwiftUI.IgnoreSolariumHardwareCheck",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
        Tweak(
            id: "lg-ignore-opt-out",
            title: "Ignore Solarium Opt-Out",
            subtitle: "Re-enable Liquid Glass where it is switched off. Respring to apply.",
            category: .liquidGlass,
            symbol: "eye.slash.fill",
            isRisky: false,
            notes: nil,
            plistModifications: [
                PlistModification(domain: .globalPreferences,
                                  key: "com.apple.SwiftUI.IgnoreSolariumOptOut",
                                  value: .bool(true))
            ],
            minIOS: "27.0",
            modifications: [],
        ),
    ]
}
