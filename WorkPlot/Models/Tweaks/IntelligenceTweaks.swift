import Foundation

/// Intelligence category tweaks.
///
/// The Siri AI Setup tab is gone — its flow now lives here as three plain
/// Tweaks-tab items, applied through the normal `GestaltStore.apply()`
/// engine (see the dedicated Intelligence pass there). They are special
/// like the device-spoof tweak: they branch on the live device identity at
/// apply time, so the declarative `GestaltModification` list can't express
/// them and each one is handled by name in `GestaltStore`.
///
/// 1. Enable Apple Intelligence — ported from `GestaltStore.applyAIRegion()`:
///    writes the US regulatory-region keys and, when this device isn't
///    natively eligible, changes the model field key (ProductType) from the
///    current iPhone to the target iPhone.
/// 2. Disable Region Lock — automatically switches the region keys to USA.
/// 3. Device Model Spoof — picker changing the model field key to a
///    selected iPhone 16 (base) through iPhone 17 Pro Max.
///
/// ALL of these need a FULL REBOOT to take effect (only PosterBoard tweaks
/// get away with a respring). Revert via Recovery (the pristine backup).
enum IntelligenceTweaks {
    static let enableIntelligenceID = "ai-enable-intelligence"
    static let usaRegionID = "ai-region-usa"
    static let modelSpoofID = "ai-model-spoof"

    /// IDs handled by the dedicated Intelligence pass in
    /// `GestaltStore.apply(only:)` — excluded from the generic
    /// modification loop the same way the device-spoof tweak is.
    static let handledIDs: Set<String> = [
        enableIntelligenceID,
        usaRegionID,
        modelSpoofID,
    ]

    /// Spoof targets for the model-field picker: iPhone 16 (base) through
    /// iPhone 17 Pro Max, in order. Defined locally (not via
    /// `DeviceSpoofingManager.targets`, which lacks the base models) so the
    /// full-identity "Device Spoof" picker's index order is untouched. The
    /// model-field spoof only consumes `productType`, `marketingName` and
    /// `regulatoryModel`; the board/CPU columns are informational.
    static let modelSpoofTargets: [SpoofTarget] = [
        SpoofTarget(marketingName: "iPhone 16", productType: "iPhone17,3", hwModel: "D921AP", cpuName: "t8140", regulatoryModel: "A3081"),
        SpoofTarget(marketingName: "iPhone 16 Pro", productType: "iPhone17,1", hwModel: "D93AP", cpuName: "t8140", regulatoryModel: "A3083"),
        SpoofTarget(marketingName: "iPhone 16 Pro Max", productType: "iPhone17,2", hwModel: "D94AP", cpuName: "t8140", regulatoryModel: "A3084"),
        SpoofTarget(marketingName: "iPhone 17", productType: "iPhone18,3", hwModel: "V51AP", cpuName: "t8150", regulatoryModel: "A3258"),
        SpoofTarget(marketingName: "iPhone 17 Pro", productType: "iPhone18,1", hwModel: "V53AP", cpuName: "t8150", regulatoryModel: "A3256"),
        SpoofTarget(marketingName: "iPhone 17 Pro Max", productType: "iPhone18,2", hwModel: "V54AP", cpuName: "t8150", regulatoryModel: "A3257"),
    ]

    static let all: [Tweak] = [
        Tweak(
            id: enableIntelligenceID,
            title: "Enable Apple Intelligence",
            subtitle: "Sets the US region keys and changes the model field key to an eligible iPhone. Requires a full reboot to take effect.",
            category: .ai,
            symbol: "brain",
            isRisky: true,
            notes: "Spoofs the model field when this device isn't natively eligible. May temporarily break Face ID. Revert via Recovery.",
            modifications: [],
        ),
        Tweak(
            id: usaRegionID,
            title: "Disable Region Lock",
            subtitle: "Automatically switches the device region to USA (LL). Requires a full reboot to take effect.",
            category: .ai,
            symbol: "globe.americas.fill",
            isRisky: true,
            notes: "Overwrites the region-code keys with the US region. Revert via Recovery.",
            modifications: [],
        ),
        Tweak(
            id: modelSpoofID,
            title: "Device Model Spoof",
            subtitle: "Changes the model field key to the selected iPhone, 16 through 17 Pro Max. Requires a full reboot to take effect.",
            category: .ai,
            symbol: "iphone.and.arrow.forward",
            isRisky: true,
            notes: "Changes the model field key only — not a full identity blast. May temporarily break Face ID. Revert via Recovery.",
            detail: .picker(options: modelSpoofTargets.map(\.marketingName)),
            modifications: [],
        ),
    ]
}
