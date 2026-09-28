import Foundation

/// AirLift-side tweaks: capabilities that ride the AirLift file-write path
/// (iOS 26.6 – 27.x) rather than MobileGestalt CacheExtra.
///
/// The coordinator wires these in by appending `AirLiftTweaks.all` to
/// `TweakCatalog.all` — do NOT edit `TweakCatalog.swift` here.
enum AirLiftTweaks {
    static let all: [Tweak] = [
        Tweak(
            id: "disable-thermal",
            title: "Disable Thermal",
            subtitle: "Not yet implemented — enabling currently changes nothing.",
            category: .system,
            symbol: "thermometer.snowflake",
            isRisky: true,
            notes: "Placeholder. There is no verified MobileGestalt key that disables the thermal daemon, so this cannot be expressed as GestaltModification(s). The real implementation needs an AirLift file write against the thermalmonitord configuration, which is not device-verified yet. Until that lands (see AirLiftFileWriter), this tweak is listed for visibility only and writes nothing.",
            modifications: []
        ),
    ]
}
