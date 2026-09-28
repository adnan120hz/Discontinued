import Foundation
import UIKit

// MARK: - Platform gating

/// Restricts a tweak to a specific device idiom. Tweaks that don't match
/// the running device's `UIUserInterfaceIdiom` are hidden from the catalog
/// entirely (see `GestaltStore`).
enum TweakPlatform: Equatable {
    case all
    case iOSOnly
    case iPadOSOnly

    func matches(_ idiom: UIUserInterfaceIdiom) -> Bool {
        switch self {
        case .all: return true
        case .iOSOnly: return idiom == .phone
        case .iPadOSOnly: return idiom == .pad
        }
    }
}

// MARK: - Categories

enum TweakCategory: String, CaseIterable, Identifiable {
    case display = "Display"
    case device = "Device"
    case system = "System"
    case liquidGlass = "Liquid Glass"
    case ipad = "iPad"
    case gestalt = "Gestalt"
    case info = "Info"
    case ai = "Intelligence"

    var id: String { rawValue }
}

// MARK: - Values

/// A plist value that can be written into CacheExtra.
enum MGValue: Equatable {
    case int(Int)
    case double(Double)
    case string(String)
    case intArray([Int])
    /// A boolean plist value. Used by preference-plist tweaks
    /// (Liquid Glass options etc.), which write real booleans.
    case bool(Bool)
    /// Delete the key (or subkey) from CacheExtra.
    case remove
    /// Leave whatever value is already in the plist untouched.
    case keepCurrent

    var plistObject: Any {
        switch self {
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .intArray(let v): return v
        case .bool(let v): return v
        case .remove, .keepCurrent: return NSNull()
        }
    }
}

// MARK: - Preference-plist modifications (non-MobileGestalt)

/// A system preference domain a tweak can write to. These are plain plist
/// files — NOT MobileGestalt's CacheExtra — so they do not need a new
/// MobileGestalt cache. Liquid Glass tweaks still need a full reboot to
/// take effect; a respring is not enough.
enum PlistDomain: Equatable, Hashable {
    /// `/var/mobile/Library/Preferences/.GlobalPreferences.plist`
    case globalPreferences
    /// `/var/mobile/Library/Preferences/com.apple.springboard.plist`
    /// (lowercase "springboard", matching `SpringBoardPlist.candidatePaths`).
    case springBoard
}

/// One key/value written into a preference plist when the owning tweak is
/// enabled. When the tweak is disabled the key is removed again, so
/// toggling off reverts the change without a full restore.
struct PlistModification: Equatable {
    let domain: PlistDomain
    let key: String
    let value: MGValue
}

// MARK: - Modifications

struct GestaltModification: Equatable {
    let key: String
    /// When set, `value` is written into `key[subkey]` instead of `key`.
    let subkey: String?
    let value: MGValue
    /// Marks the modification driven by a `.picker` detail so only that
    /// value is swapped for the selected option.
    var isPicker: Bool = false
    /// When set, `value` is written into the `CacheData` blob at the offset
    var cacheDataKey: String? = nil
    /// Value written into CacheData when the owning tweak is disabled.
    var cacheDataDisabledValue: Int? = nil
}

// MARK: - Detail (inline editors)

enum TweakDetail: Equatable {
    case picker(options: [String])
    case textField(placeholder: String, keyboard: TextFieldKind)
}

enum TextFieldKind: Equatable {
    case plain
    case numeric
}

// MARK: - Tweak

struct Tweak: Identifiable, Equatable {
    /// Applied via DeviceSpoofingManager instead of plain modifications.
    static let deviceSpoofTweakID = "devicespoof"

    let id: String
    let title: String
    let subtitle: String
    let category: TweakCategory
    let symbol: String
    let isRisky: Bool
    /// Optional per-tweak notes shown under the row when risky.
    let notes: String?

    var isEnabled: Bool = false
    var detail: TweakDetail?
    var selectedIndex: Int = 0
    var textValue: String = ""
    /// For `.picker` details: the values that map 1:1 to `options`.
    /// Use `.remove` / `.keepCurrent` for "Default"/"Original" options.
    var pickerValues: [MGValue] = []

    /// Special flag for iPadOS: requires the CacheData binary patch.
    var requiresCacheDataPatch: Bool = false

    /// Restricts which device idiom this tweak is offered on. Defaults to
    /// `.all` (both iPhone and iPad).
    var platform: TweakPlatform = .all

    /// When true, applying this tweak writes the SpringBoard
    /// `SBSuppressDynamicIslandCompletely` flag (true = hide Dynamic Island,
    /// false = restore it) instead of a Gestalt CacheExtra modification.
    var springBoardSuppression: Bool = false

    /// Preference-plist writes for this tweak (Liquid Glass options etc.).
    /// Empty for pure MobileGestalt tweaks.
    var plistModifications: [PlistModification] = []

    /// Optional iOS version gate, as "major.minor" or "major.minor.patch"
    /// (e.g. "26.5"). Tweaks outside their gate are hidden from the catalog
    /// and skipped at apply time.
    var minIOS: String? = nil
    var maxIOS: String? = nil

    let modifications: [GestaltModification]

    /// True when the running iOS satisfies this tweak's `minIOS`/`maxIOS`
    /// gate. Tweaks without a gate are supported everywhere.
    func isSupportedOnCurrentOS() -> Bool {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        if let min = minIOS,
           Self.compareVersions(current, to: min) == .orderedAscending {
            return false
        }
        if let max = maxIOS,
           Self.compareVersions(current, to: max) == .orderedDescending {
            return false
        }
        return true
    }

    /// Compares an `OperatingSystemVersion` against a "major.minor[.patch]"
    /// string. Missing components default to 0.
    private static func compareVersions(_ current: OperatingSystemVersion,
                                        to versionString: String) -> ComparisonResult {
        let parts = versionString.split(separator: ".").compactMap { Int($0) }
        let target = (parts.count > 0 ? parts[0] : 0,
                      parts.count > 1 ? parts[1] : 0,
                      parts.count > 2 ? parts[2] : 0)
        let actual = (current.majorVersion, current.minorVersion, current.patchVersion)
        if actual < target { return .orderedAscending }
        if actual > target { return .orderedDescending }
        return .orderedSame
    }
}
