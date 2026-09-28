import Foundation

/// AirLift-side tweaks: capabilities that ride the AirLift file-write path
/// (iOS 26.6 – 27.x) rather than MobileGestalt CacheExtra.
///
/// The coordinator wires these in by appending `AirLiftTweaks.all` to
/// `TweakCatalog.all` — do NOT edit `TweakCatalog.swift` here.
enum AirLiftTweaks {
    static let all: [Tweak] = []
}
