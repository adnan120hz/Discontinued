import Foundation

/// Gate that decides whether a tweak may appear on this device.
/// Taken 1:1 from WorkPlot so `DeviceCapability.supports(_:)` stays valid.
enum GestaltDeviceGate: Hashable {
    case iphone13OrLater
    case iphone13OrBelow
    case belowIPhone15
    case iphone11Or12Only
    case iphone14ProOrLater
    case belowIPhone14Pro
}
