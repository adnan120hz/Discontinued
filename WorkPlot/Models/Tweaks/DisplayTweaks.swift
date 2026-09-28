import Foundation

/// Display category tweaks.
enum DisplayTweaks {
    static let all: [Tweak] = [
        // Dynamic Island enable — VERIFIED, do not "fix".
        //
        // The obfuscated key "YlEtTtHlNesRBMal1CqRaA" (= DeviceSupportsDynamicIsland)
        // with value 1 is the community-proven enable override:
        //  - Nugget >= 7.2 "Enable Dynamic Island on any device" writes exactly
        //    this key = 1 (leminlimez/nugget#816: "just set YlEtTtHlNesRBMal1CqRaA
        //    to 1 ... theres no need to change the ArtworkDeviceSubType").
        //  - SparseBox's feature-flag table lists YlEtTtHlNesRBMal1CqRaA as the
        //    MobileGestalt key that "Enables Dynamic Island UI".
        //
        // It is an ENABLE-ONLY override: writing 0 leaves the hardware default,
        // so it cannot remove the island on native-island devices — use the
        // "Disable Dynamic Island" SpringBoard tweak below for that. Reported
        // brokenness is most likely a missing respring or a conflicting
        // ArtworkDeviceSubType pick, not this key.
        Tweak(
            id: "dynamic-island",
            title: "Dynamic Island",
            subtitle: "Force the Dynamic Island capability bit directly.",
            category: .display,
            symbol: "rectangle.inset.filled",
            isRisky: false,
            notes: "Enable-only override (matches Nugget ≥ 7.2). Takes effect after a full device restart; does not remove the island on devices that have one natively.",
            modifications: [
                GestaltModification(key: "YlEtTtHlNesRBMal1CqRaA",
                                    subkey: nil, value: .int(1))
            ]
        ),
        Tweak(
            id: "disable-dynamic-island",
            title: "Disable Dynamic Island",
            subtitle: "Hide the Dynamic Island completely (restart device to apply).",
            category: .display,
            symbol: "eye.slash",
            isRisky: false,
            notes: "Writes SBSuppressDynamicIslandCompletely to the SpringBoard preferences.",
            springBoardSuppression: true,
            modifications: []
        ),
        Tweak(
            id: "aod",
            title: "Always-On Display",
            subtitle: "Enable Always-On Display support.",
            category: .display,
            symbol: "sun.max.fill",
            isRisky: false,
            notes: nil,
            modifications: [
                GestaltModification(key: "2OOJf1VhaM7NxfRok3HbWQ",
                                    subkey: nil, value: .int(1)),
                GestaltModification(key: "j8/Omm6s1lsmTDFsXjsBfA",
                                    subkey: nil, value: .int(1)),
            ]
        ),
        Tweak(
            id: "aod-vibrancy",
            title: "AOD Vibrancy",
            subtitle: "Enable the Always-On Display vibrancy effect.",
            category: .display,
            symbol: "sparkles",
            isRisky: false,
            notes: nil,
            modifications: [
                GestaltModification(key: "ykpu7qyhqFweVMKtxNylWA",
                                    subkey: nil, value: .int(1))
            ]
        ),
        Tweak(
            id: "pwm",
            title: "Pulse Width Modulation",
            subtitle: "Advertise PWM display support.",
            category: .display,
            symbol: "waveform",
            isRisky: false,
            notes: nil,
            modifications: [
                GestaltModification(key: "6IejgN+1Fmu5/QrZFOIeNw",
                                    subkey: nil, value: .int(1))
            ]
        ),
    ]
}
