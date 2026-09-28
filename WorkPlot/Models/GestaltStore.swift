import Foundation
import SwiftUI

// MARK: - Errors

enum ApplyError: LocalizedError {
    case noTweaksSelected
    case busy
    case activationFailed
    case missingPath
    case badPlist
    case missingCacheData
    case noBackup
    case writeFailed
    case writeVerificationFailed
    case restoreVerificationFailed
    case appleIntelligenceNotReady
    case invalidSelection(String)

    var errorDescription: String? {
        switch self {
        case .noTweaksSelected: return "Select at least one tweak first."
        case .busy: return "Another operation is in progress."
        case .activationFailed: return "Could not obtain access to the MobileGestalt cache on this device."
        case .missingPath: return "The MobileGestalt path is unavailable."
        case .badPlist: return "The MobileGestalt plist could not be parsed."
        case .missingCacheData: return "CacheData is missing from the MobileGestalt plist."
        case .noBackup: return "No backup exists yet. Apply tweaks once to create one."
        case .writeFailed: return "The write to the MobileGestalt plist failed."
        case .writeVerificationFailed: return "The write did not verify. The original file was restored."
        case .restoreVerificationFailed: return "The restore did not verify. Please try again."
        case .appleIntelligenceNotReady: return "Apple Intelligence must be applied first (A62OafQ85EJAiiqKn4agtg must be 1)."
        case .invalidSelection(let title): return "\(title): invalid selection, skipped."
        }
    }
}

// MARK: - Results

struct ApplyResult: Equatable {
    let appliedCount: Int
    let warnings: [String]
    let binaryPatchApplied: Bool
    let backedUpFirstTime: Bool
}

struct RestoreResult: Equatable {
    let byteCount: Int
}

// MARK: - Store

@MainActor
final class GestaltStore: ObservableObject {

    @Published var tweaks: [Tweak] = []
    @Published private(set) var isBusy = false
    @Published private(set) var lastApply: ApplyResult?
    @Published private(set) var lastRestore: RestoreResult?
    @Published private(set) var isDeviceSpoofed = false
    @Published var lastError: String?

    let backup = BackupManager()

    var enabledCount: Int { tweaks.filter(\.isEnabled).count }
    var backupInfo: BackupManager.BackupInfo? { backup.info }

    // MARK: Persistence

    private let defaults = UserDefaults.standard

    private static func key(_ field: String, _ id: String) -> String {
        "tweak.\(field).\(id)"
    }

    private func loadTweakState() {
        for idx in tweaks.indices {
            let id = tweaks[idx].id
            tweaks[idx].isEnabled = defaults.bool(forKey: Self.key("enabled", id))
            tweaks[idx].selectedIndex = defaults.object(forKey: Self.key("picker", id)) as? Int ?? tweaks[idx].selectedIndex
            tweaks[idx].textValue = defaults.string(forKey: Self.key("text", id)) ?? tweaks[idx].textValue
        }
    }

    init() {
        // iOS-gated tweaks (e.g. Liquid Glass options) are only *offered* on
        // the versions they support — see Tweak.isSupportedOnCurrentOS().
        tweaks = TweakCatalog.available().filter { $0.isSupportedOnCurrentOS() }
        loadTweakState()
    }

    // MARK: Toggle plumbing

    func isEnabled(_ id: String) -> Bool {
        tweaks.first { $0.id == id }?.isEnabled ?? false
    }

    func setEnabled(_ on: Bool, for id: String) {
        guard let idx = tweaks.firstIndex(where: { $0.id == id }) else { return }
        tweaks[idx].isEnabled = on
        defaults.set(on, forKey: Self.key("enabled", id))
    }

    func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(id) },
            set: { self.setEnabled($0, for: id) }
        )
    }

    func pickerBinding(for id: String) -> Binding<Int> {
        Binding(
            get: { self.tweaks.first { $0.id == id }?.selectedIndex ?? 0 },
            set: { v in
                guard let idx = self.tweaks.firstIndex(where: { $0.id == id }) else { return }
                self.tweaks[idx].selectedIndex = v
                self.defaults.set(v, forKey: Self.key("picker", id))
            }
        )
    }

    func textBinding(for id: String) -> Binding<String> {
        Binding(
            get: { self.tweaks.first { $0.id == id }?.textValue ?? "" },
            set: { v in
                guard let idx = self.tweaks.firstIndex(where: { $0.id == id }) else { return }
                self.tweaks[idx].textValue = v
                self.defaults.set(v, forKey: Self.key("text", id))
            }
        )
    }

    func resetToggles() {
        for idx in tweaks.indices { tweaks[idx].isEnabled = false }
        lastError = nil
    }

    // MARK: AI Region key snapshot

    /// CacheExtra keys carrying the device-identity spoof. `unspoofDevice()`
    /// reverses only these, leaving the Siri/eligibility keys in place.
    private static let spoofKeys = [
        "h9jDsbgj7xIVeIQ8S3/X3Q", // ProductType
        "oYicEKzVTz4/CxxE05pEgQ", // HardwareModel
        "5pYKlGnYYBzGvAlIU8RjEQ", // CPU model
    ]

    /// CacheExtra keys carrying Siri / Apple Intelligence eligibility.
    private static let siriKeys = [
        "A62OafQ85EJAiiqKn4agtg",
        "h63QSdBCiT/z0WU6rdQv6Q",
        "yK+xavymRGZ3xWc1tb8XDg",
        "97JDvERpVwO+GHtthIh7hA",
    ]

    /// Every CacheExtra key the Siri / Apple Intelligence / Siri AI flow can
    /// touch. `applySiri()` reverses these back to their saved values.
    private static var aiRegionKeys: [String] { siriKeys + spoofKeys }

    private static func aiRegionSnapshotPresenceKey(_ key: String) -> String { "aiRegionBackup.hasValue.\(key)" }
    private static func aiRegionSnapshotValueKey(_ key: String) -> String { "aiRegionBackup.value.\(key)" }

    /// Saves a key's current value into the app's own container (UserDefaults)
    /// the first time it's touched, so it can be reversed later. Never
    /// overwrites an existing snapshot — it always holds the value from
    /// before WorkPlot first modified the key.
    private func snapshotAIRegionKeyIfNeeded(_ key: String, in cacheExtra: [String: Any]) {
        let presenceKey = Self.aiRegionSnapshotPresenceKey(key)
        guard defaults.object(forKey: presenceKey) == nil else { return }
        if let value = cacheExtra[key] {
            defaults.set(value, forKey: Self.aiRegionSnapshotValueKey(key))
            defaults.set(true, forKey: presenceKey)
        } else {
            defaults.set(false, forKey: presenceKey)
        }
    }

    /// Applies the device-identity spoof when `configuration` calls for one,
    /// snapshotting each key first. Devices already eligible for Apple
    /// Intelligence resolve to no spoof and are left untouched. Returns a
    /// warning describing the spoof, or `nil` when none was needed.
    private func applySpoof(_ configuration: AIRegionConfiguration,
                            to cacheExtra: inout [String: Any]) -> String? {
        guard let productType = configuration.spoofedProductType,
              let hardwareModel = configuration.spoofedHardwareModel,
              let cpuModel = configuration.spoofedCPUModel else { return nil }
        for key in Self.spoofKeys { snapshotAIRegionKeyIfNeeded(key, in: cacheExtra) }
        cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] = productType
        cacheExtra["oYicEKzVTz4/CxxE05pEgQ"] = hardwareModel
        cacheExtra["5pYKlGnYYBzGvAlIU8RjEQ"] = cpuModel
        return "Device wasn't natively eligible — spoofed to \(configuration.profile.marketingName) (\(configuration.profile.regulatoryModel))."
    }

    // MARK: - Intelligence tweaks (Tweaks tab)

    /// Applies one of the three Intelligence tweaks to an in-memory
    /// CacheExtra copy, ported from the old SiriAISetupView flow
    /// (`applyAIRegion()` + `applySpoof()`). Every key is snapshotted
    /// before its first write, exactly like that flow, so the changes stay
    /// reversible through the same snapshot machinery. Returns an optional
    /// warning for the caller to surface.
    private func applyIntelligenceTweak(_ tweak: Tweak,
                                        to cacheExtra: inout [String: Any]) throws -> String? {
        switch tweak.id {
        case IntelligenceTweaks.enableIntelligenceID:
            return applyIntelligenceEnable(to: &cacheExtra)
        case IntelligenceTweaks.usaRegionID:
            applyUSARegion(to: &cacheExtra)
            return nil
        case IntelligenceTweaks.modelSpoofID:
            let targets = IntelligenceTweaks.modelSpoofTargets
            guard tweak.selectedIndex >= 0, tweak.selectedIndex < targets.count else {
                throw ApplyError.invalidSelection(tweak.title)
            }
            applyModelFieldSpoof(targets[tweak.selectedIndex], to: &cacheExtra)
            return nil
        default:
            return nil
        }
    }

    /// "Enable Apple Intelligence": sets the US regulatory-region keys and,
    /// when this device isn't natively eligible, changes the model field
    /// key (ProductType) from the current iPhone to the target iPhone —
    /// the `applyAIRegion()` port.
    private func applyIntelligenceEnable(to cacheExtra: inout [String: Any]) -> String? {
        let configuration = AIRegionConfiguration.resolve(for: cacheExtra)

        for key in Self.siriKeys {
            snapshotAIRegionKeyIfNeeded(key, in: cacheExtra)
        }
        let spoofWarning = applySpoof(configuration, to: &cacheExtra)

        cacheExtra["A62OafQ85EJAiiqKn4agtg"] = 1
        cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] = "LL"
        cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] = "LL/A"
        cacheExtra["97JDvERpVwO+GHtthIh7hA"] = configuration.profile.regulatoryModel

        if let spoofWarning {
            return spoofWarning
        }
        return "This device is already Apple Intelligence eligible — the model field key was left as \(configuration.profile.marketingName)."
    }

    /// "Disable Region Lock": automatically switches the region-code keys
    /// to USA (LL / LL-A).
    private func applyUSARegion(to cacheExtra: inout [String: Any]) {
        for key in ["h63QSdBCiT/z0WU6rdQv6Q", "yK+xavymRGZ3xWc1tb8XDg"] {
            snapshotAIRegionKeyIfNeeded(key, in: cacheExtra)
        }
        cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] = "LL"
        cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] = "LL/A"
    }

    /// "Device Model Spoof": changes the model field key — the ProductType
    /// key family plus the marketing name (when already cached) and the
    /// regulatory model number — from the current iPhone to the target
    /// iPhone. Deliberately NOT a full identity blast: board and CPU keys
    /// are left alone.
    private func applyModelFieldSpoof(_ target: SpoofTarget,
                                     to cacheExtra: inout [String: Any]) {
        let keys = DeviceSpoofingManager.productTypeKeys
            + DeviceSpoofingManager.regulatoryModelKeys
        for key in keys {
            snapshotAIRegionKeyIfNeeded(key, in: cacheExtra)
        }
        for key in DeviceSpoofingManager.productTypeKeys {
            cacheExtra[key] = target.productType
        }
        for key in DeviceSpoofingManager.deviceNameKeys where cacheExtra[key] != nil {
            snapshotAIRegionKeyIfNeeded(key, in: cacheExtra)
            cacheExtra[key] = target.marketingName
        }
        cacheExtra[DeviceSpoofingManager.regulatoryModelKeys[0]] = target.regulatoryModel
    }

    /// True when CacheExtra advertises a product type other than the real
    /// hardware. Reads the live plist, so it reflects spoofs applied by any
    /// route — not just this session.
    func refreshSpoofState() async {
        guard !isBusy else { return }
        let access = MobileGestaltAccess()
        guard (try? access.activate()) != nil else { return }
        defer { access.deactivate() }
        guard let path = access.mobileGestaltPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = parsed as? [String: Any],
              let cacheExtra = plist["CacheExtra"] as? [String: Any]
        else { return }
        let reported = cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String
        isDeviceSpoofed = reported != nil && reported != AIRegionProfile.machineIdentifier
    }

    // MARK: Preference-plist writes

    /// Candidate on-device locations for each preference domain, in probe
    /// order. The GlobalPreferences path is the HomeDomain copy GoldenNugget
    /// mirrors into so tweaks survive the NSGlobalDomain search chain; the
    /// SpringBoard candidates are `SpringBoardPlist.candidatePaths`
    /// (lowercase "springboard" — that is the real on-device filename).
    ///
    /// Internal (not private) so the liquid-glass backup flow
    /// (`LiquidGlassBackupFlow.swift`) can snapshot and restore the same
    /// files through the same probe order.
    static func preferencePlistPaths(for domain: PlistDomain) -> [String] {
        switch domain {
        case .globalPreferences:
            return [
                "/var/mobile/Library/Preferences/.GlobalPreferences.plist",
                "/private/var/mobile/Library/Preferences/.GlobalPreferences.plist",
            ]
        case .springBoard:
            return SpringBoardPlist.candidatePaths
        }
    }

    /// True when two plist scalars are equal (bridged through NSObject).
    private static func plistScalarsEqual(_ current: Any?, _ new: Any) -> Bool {
        guard let current, let newObject = new as? NSObject else { return false }
        return (current as? NSObject)?.isEqual(newObject) ?? false
    }

    /// Applies one tweak's `PlistModification`s to every reachable copy of
    /// the target preference files: enabled writes the value, disabled
    /// removes the key. Each file is merged (unrelated keys are preserved),
    /// serialized in its original format, and written with the same
    /// probe + bad_query lease + verified in-place write that
    /// `SpringBoardPlist.setSuppressed` uses — a plain
    /// `FileSystemAccessor.writePlist` createFile cannot survive the sandbox
    /// escape (EPERM without the lease), so the lease path is used instead.
    /// Returns the number of files actually changed.
    ///
    /// Internal (not private) so the liquid-glass backup flow
    /// (`LiquidGlassBackupFlow.swift`) reuses this exact write path instead
    /// of duplicating it.
    @discardableResult
    static func applyPlistModifications(_ mods: [PlistModification],
                                        enabled: Bool,
                                        warnings: inout [String]) -> Int {
        var changed = 0
        let byDomain = Dictionary(grouping: mods, by: \.domain)
        for (domain, entries) in byDomain {
            var reachedAny = false
            for path in preferencePlistPaths(for: domain) {
                guard let data = FileManager.default.contents(atPath: path) else { continue }
                var format = PropertyListSerialization.PropertyListFormat.binary
                guard var plist = (try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: &format)) as? [String: Any] else { continue }
                reachedAny = true
                var dirty = false
                for entry in entries {
                    if enabled {
                        switch entry.value {
                        case .remove, .keepCurrent:
                            break
                        default:
                            let newValue = entry.value.plistObject
                            if !plistScalarsEqual(plist[entry.key], newValue) {
                                plist[entry.key] = newValue
                                dirty = true
                            }
                        }
                    } else if plist[entry.key] != nil {
                        plist.removeValue(forKey: entry.key)
                        dirty = true
                    }
                }
                guard dirty else { continue }
                do {
                    let out = try PropertyListSerialization.data(
                        fromPropertyList: plist, format: format, options: 0)
                    try BadQueryLeaseScope.withLease(forPath: path) {
                        try InodeWriter.writeVerifiedInPlace(out, to: path)
                    }
                    changed += 1
                } catch {
                    warnings.append("\(path): preference write failed — \(error.localizedDescription)")
                }
            }
            if !reachedAny {
                warnings.append("Preference file for \(domain) is not reachable on this device — skipped.")
            }
        }
        return changed
    }

    // MARK: Engine

    /// Reads the live plist, applies every enabled tweak to an in-memory
    /// copy, writes it back in place (preserving ownership/permissions) and
    /// verifies the read-back. If verification fails the pristine backup is
    /// restored automatically so the device is never left in a broken state.
    func apply() async throws -> ApplyResult {
        try await apply(only: nil)
    }

    /// Same engine as `apply()`, but restricted to the given tweak IDs —
    /// tweaks staged elsewhere in the app (e.g. the Tweaks console) are left
    /// untouched even if they're currently enabled.
    func apply(only ids: Set<String>) async throws -> ApplyResult {
        try await apply(only: ids as Set<String>?)
    }

    private func apply(only ids: Set<String>?) async throws -> ApplyResult {
        let inScope = tweaks.filter { ids == nil || ids!.contains($0.id) }
        let scopedEnabledCount = inScope.filter(\.isEnabled).count
        // Toggling a preference-plist tweak OFF still has work to do (its
        // keys are removed), so a pure "revert" pass is allowed with nothing
        // enabled.
        let scopedPlistRevertCount = inScope.filter { !$0.isEnabled && !$0.plistModifications.isEmpty }.count
        guard scopedEnabledCount > 0 || scopedPlistRevertCount > 0 else { throw ApplyError.noTweaksSelected }
        guard !isBusy else { throw ApplyError.busy }
        isBusy = true
        defer { isBusy = false }

        let access = MobileGestaltAccess()
        guard (try? access.activate()) != nil else {
            throw ApplyError.activationFailed
        }
        defer { access.deactivate() }

        guard let path = access.mobileGestaltPath else { throw ApplyError.missingPath }
        let url = URL(fileURLWithPath: path)

        let current = try Data(contentsOf: url)

        // Pristine backup — created once from the untouched file.
        let hadBackup = backup.hasBackup
        try backup.ensureBackup(from: current)

        guard var plist = try PropertyListSerialization.propertyList(
            from: current, format: nil) as? [String: Any]
        else { throw ApplyError.badPlist }

        var cacheExtra = (plist["CacheExtra"] as? [String: Any]) ?? [:]
        var applied = 0
        var warnings: [String] = []

        for tweak in tweaks where tweak.isEnabled && (ids == nil || ids!.contains(tweak.id)) && tweak.id != Tweak.deviceSpoofTweakID && !IntelligenceTweaks.handledIDs.contains(tweak.id) {
            do {
                var mods = tweak.modifications
                if let detail = tweak.detail {
                    switch detail {
                    case .picker(let options):
                        guard tweak.selectedIndex >= 0 && tweak.selectedIndex < options.count else {
                            warnings.append("\(tweak.title): invalid picker selection, skipped.")
                            continue
                        }
                        guard tweak.selectedIndex < tweak.pickerValues.count else {
                            warnings.append("\(tweak.title): picker values mismatch, skipped.")
                            continue
                        }
                        // Replace the picker value with the selected option.
                        let selectedValue = tweak.pickerValues[tweak.selectedIndex]
                        mods = tweak.modifications.map { m in
                            if m.isPicker {
                                return GestaltModification(key: m.key, subkey: m.subkey,
                                                           value: selectedValue)
                            }
                            return m
                        }
                        applied += 1
                    case .textField:
                        if tweak.textValue.isEmpty {
                            warnings.append("\(tweak.title): no text entered, skipped.")
                            continue
                        } else {
                            mods = tweak.modifications.map { m in
                                GestaltModification(key: m.key, subkey: m.subkey,
                                                    value: .string(tweak.textValue))
                            }
                            applied += 1
                        }
                    }
                } else {
                    if !tweak.springBoardSuppression { applied += 1 }
                }
                for mod in mods {
                    switch mod.value {
                    case .remove:
                        if let subkey = mod.subkey {
                            if var dict = cacheExtra[mod.key] as? [String: Any] {
                                dict.removeValue(forKey: subkey)
                                cacheExtra[mod.key] = dict
                            }
                        } else {
                            cacheExtra.removeValue(forKey: mod.key)
                        }
                    case .keepCurrent:
                        break
                    default:
                        if let subkey = mod.subkey {
                            var dict = (cacheExtra[mod.key] as? [String: Any]) ?? [:]
                            dict[subkey] = mod.value.plistObject
                            cacheExtra[mod.key] = dict
                        } else {
                            cacheExtra[mod.key] = mod.value.plistObject
                        }
                    }
                }
            }
        }

        // SpringBoard Dynamic Island suppression — enabled hides the island,
        // disabled restores it. Idempotent, so harmless on every apply.
        for tweak in tweaks where (ids == nil || ids!.contains(tweak.id)) && tweak.springBoardSuppression {
            do {
                _ = try SpringBoardPlist.setSuppressed(tweak.isEnabled)
                applied += 1
            } catch {
                warnings.append("\(tweak.title): \(error.localizedDescription)")
            }
        }

        // Intelligence tweaks (Tweaks tab): Enable Apple Intelligence, the
        // US region switch, and the iPhone 16 → 17 Pro Max model-field
        // spoof. They branch on the live device identity like the old
        // SiriAISetupView flow did, so they run here — on the same in-memory
        // CacheExtra — instead of the declarative loop above.
        for tweak in tweaks where tweak.isEnabled && (ids == nil || ids!.contains(tweak.id)) && IntelligenceTweaks.handledIDs.contains(tweak.id) {
            do {
                if let warning = try applyIntelligenceTweak(tweak, to: &cacheExtra) {
                    warnings.append(warning)
                }
                applied += 1
            } catch {
                warnings.append(error.localizedDescription)
            }
        }

        plist["CacheExtra"] = cacheExtra

        // Full-identity device spoof — runs after the generic pass above so
        // its CacheExtra writes aren't clobbered by the stale local copy.
        // Index 0 ("None") is a no-op; the manager refuses loudly (throws)
        // when CacheExtra/ArtworkDevice is missing, aborting before any
        // disk write happens.
        for tweak in tweaks where tweak.isEnabled && (ids == nil || ids!.contains(tweak.id)) && tweak.id == Tweak.deviceSpoofTweakID {
            let index = tweak.selectedIndex
            guard index > 0, index - 1 < DeviceSpoofingManager.targets.count else {
                warnings.append("\(tweak.title): invalid picker selection, skipped.")
                continue
            }
            try DeviceSpoofingManager.apply(DeviceSpoofingManager.targets[index - 1], to: &plist)
            applied += 1
        }

        // Optional binary patch (iPadOS).
        var binaryPatch = false
        if tweaks.contains(where: { $0.isEnabled && $0.requiresCacheDataPatch && (ids == nil || ids!.contains($0.id)) }) {
            guard let cacheData = plist["CacheData"] as? Data else {
                throw ApplyError.missingCacheData
            }
            plist["CacheData"] = try CacheDataPatch.apply(to: cacheData)
            binaryPatch = true
        }

        var cacheDataPatches: [(key: String, value: Int)] = []
        for tweak in tweaks where ids == nil || ids!.contains(tweak.id) {
            for mod in tweak.modifications where mod.cacheDataKey != nil {
                let patchValue: Int
                if tweak.isEnabled {
                    guard case .int(let v) = mod.value else { continue }
                    patchValue = v
                } else {
                    patchValue = mod.cacheDataDisabledValue ?? 0
                }
                cacheDataPatches.removeAll { $0.key == mod.cacheDataKey }
                cacheDataPatches.append((mod.cacheDataKey!, patchValue))
            }
        }
        if !cacheDataPatches.isEmpty {
            guard var cacheData = plist["CacheData"] as? Data else {
                throw ApplyError.missingCacheData
            }
            var appliedCacheData = false
            for patch in cacheDataPatches {
                do {
                    try CacheDataPatch.set(patch.value, forKey: patch.key, in: &cacheData)
                    appliedCacheData = true
                } catch {
                    warnings.append("CacheData offset unavailable for key \(patch.key) on this iOS — skipped.")
                }
            }
            if appliedCacheData {
                plist["CacheData"] = cacheData
                binaryPatch = true
            }
        }

        let newData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)

        do {
            try newData.write(to: url, options: []) // in place: keeps uid/gid
        } catch {
            // Never leave the device half-written.
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeFailed
        }

        // Verify read-back; self-heal from the pristine backup on mismatch.
        guard let readback = try? Data(contentsOf: url), readback == newData else {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeVerificationFailed
        }

        // Preference-plist tweaks (Liquid Glass options, supervision text,
        // …): enabled writes the value, disabled removes the key so toggling
        // off reverts cleanly. Runs after the MobileGestalt write verified,
        // so a failed MG apply never leaves half-applied preference state.
        for tweak in tweaks where (ids == nil || ids!.contains(tweak.id)) && !tweak.plistModifications.isEmpty {
            guard tweak.isSupportedOnCurrentOS() else {
                warnings.append("\(tweak.title): not supported on this iOS version, skipped.")
                continue
            }
            let changed = Self.applyPlistModifications(tweak.plistModifications,
                                                       enabled: tweak.isEnabled,
                                                       warnings: &warnings)
            if changed > 0 { applied += 1 }
        }

        let result = ApplyResult(
            appliedCount: applied,
            warnings: warnings,
            binaryPatchApplied: binaryPatch,
            backedUpFirstTime: !hadBackup
        )
        lastApply = result
        lastError = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        return result
    }

    /// Ported 1:1 from GestaltEdit's "Enable Siri AI (US Region)" — always
    /// sets the US regulatory region keys, and if this device isn't already
    /// an Apple Intelligence-eligible model, additionally spoofs its
    /// identity to one that is. See `AIRegionConfiguration`.
    func applyAIRegion() async throws -> ApplyResult {
        guard !isBusy else { throw ApplyError.busy }
        isBusy = true
        defer { isBusy = false }

        let access = MobileGestaltAccess()
        guard (try? access.activate()) != nil else {
            throw ApplyError.activationFailed
        }
        defer { access.deactivate() }

        guard let path = access.mobileGestaltPath else { throw ApplyError.missingPath }
        let url = URL(fileURLWithPath: path)

        let current = try Data(contentsOf: url)

        let hadBackup = backup.hasBackup
        try backup.ensureBackup(from: current)

        guard var plist = try PropertyListSerialization.propertyList(
            from: current, format: nil) as? [String: Any]
        else { throw ApplyError.badPlist }

        var cacheExtra = (plist["CacheExtra"] as? [String: Any]) ?? [:]

        let configuration = AIRegionConfiguration.resolve(for: cacheExtra)
        var warnings: [String] = []

        // Save each key's pre-existing value into the app's own container
        // before overwriting it, so applySiri() can reverse this later.
        for key in Self.siriKeys {
            snapshotAIRegionKeyIfNeeded(key, in: cacheExtra)
        }
        if let warning = applySpoof(configuration, to: &cacheExtra) {
            warnings.append(warning)
        }

        cacheExtra["A62OafQ85EJAiiqKn4agtg"] = 1
        cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] = "LL"
        cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] = "LL/A"
        cacheExtra["97JDvERpVwO+GHtthIh7hA"] = configuration.profile.regulatoryModel

        plist["CacheExtra"] = cacheExtra

        let newData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)

        do {
            try newData.write(to: url, options: [])
        } catch {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeFailed
        }

        guard let readback = try? Data(contentsOf: url), readback == newData else {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeVerificationFailed
        }

        let result = ApplyResult(
            appliedCount: 1,
            warnings: warnings,
            binaryPatchApplied: false,
            backedUpFirstTime: !hadBackup
        )
        lastApply = result
        lastError = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        isDeviceSpoofed = configuration.requiresDeviceSpoofing
        return result
    }

    /// Reverses whatever `applyAIRegion()` changed — restores every AI
    /// region key to the value `snapshotAIRegionKeyIfNeeded` saved before
    /// WorkPlot first touched it (removing keys that didn't exist before),
    /// then forces `A62OafQ85EJAiiqKn4agtg` back to 0 regardless of what
    /// that restore produced.
    func applySiri() async throws -> ApplyResult {
        guard !isBusy else { throw ApplyError.busy }
        isBusy = true
        defer { isBusy = false }

        let access = MobileGestaltAccess()
        guard (try? access.activate()) != nil else {
            throw ApplyError.activationFailed
        }
        defer { access.deactivate() }

        guard let path = access.mobileGestaltPath else { throw ApplyError.missingPath }
        let url = URL(fileURLWithPath: path)

        let current = try Data(contentsOf: url)

        let hadBackup = backup.hasBackup
        try backup.ensureBackup(from: current)

        guard var plist = try PropertyListSerialization.propertyList(
            from: current, format: nil) as? [String: Any]
        else { throw ApplyError.badPlist }

        var cacheExtra = (plist["CacheExtra"] as? [String: Any]) ?? [:]

        for key in Self.aiRegionKeys {
            let presenceKey = Self.aiRegionSnapshotPresenceKey(key)
            guard defaults.object(forKey: presenceKey) != nil else { continue }
            if defaults.bool(forKey: presenceKey) {
                cacheExtra[key] = defaults.object(forKey: Self.aiRegionSnapshotValueKey(key))
            } else {
                cacheExtra.removeValue(forKey: key)
            }
        }
        cacheExtra["A62OafQ85EJAiiqKn4agtg"] = 0

        plist["CacheExtra"] = cacheExtra

        let newData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)

        do {
            try newData.write(to: url, options: [])
        } catch {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeFailed
        }

        guard let readback = try? Data(contentsOf: url), readback == newData else {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeVerificationFailed
        }

        let result = ApplyResult(
            appliedCount: 1,
            warnings: [],
            binaryPatchApplied: false,
            backedUpFirstTime: !hadBackup
        )
        lastApply = result
        lastError = nil
        isDeviceSpoofed = false
        return result
    }

    /// Siri AI requires Apple Intelligence to already be set up
    /// (`A62OafQ85EJAiiqKn4agtg == 1`) — spoofs the device identity when
    /// needed, then bumps the key to 2.
    func applySiriAI() async throws -> ApplyResult {
        guard !isBusy else { throw ApplyError.busy }
        isBusy = true
        defer { isBusy = false }

        let access = MobileGestaltAccess()
        guard (try? access.activate()) != nil else {
            throw ApplyError.activationFailed
        }
        defer { access.deactivate() }

        guard let path = access.mobileGestaltPath else { throw ApplyError.missingPath }
        let url = URL(fileURLWithPath: path)

        let current = try Data(contentsOf: url)

        guard var plist = try PropertyListSerialization.propertyList(
            from: current, format: nil) as? [String: Any]
        else { throw ApplyError.badPlist }
        var cacheExtra = (plist["CacheExtra"] as? [String: Any]) ?? [:]

        guard (cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int) == 1 else {
            throw ApplyError.appleIntelligenceNotReady
        }

        let hadBackup = backup.hasBackup
        try backup.ensureBackup(from: current)

        let configuration = AIRegionConfiguration.resolve(for: cacheExtra)
        var warnings: [String] = []
        snapshotAIRegionKeyIfNeeded("A62OafQ85EJAiiqKn4agtg", in: cacheExtra)
        if let warning = applySpoof(configuration, to: &cacheExtra) {
            warnings.append(warning)
        }

        cacheExtra["A62OafQ85EJAiiqKn4agtg"] = 2
        plist["CacheExtra"] = cacheExtra

        let newData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)

        do {
            try newData.write(to: url, options: [])
        } catch {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeFailed
        }

        guard let readback = try? Data(contentsOf: url), readback == newData else {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeVerificationFailed
        }

        let result = ApplyResult(
            appliedCount: 1,
            warnings: warnings,
            binaryPatchApplied: false,
            backedUpFirstTime: !hadBackup
        )
        lastApply = result
        lastError = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        isDeviceSpoofed = configuration.requiresDeviceSpoofing
        return result
    }

    /// Removes only the device-identity spoof, restoring each spoof key to
    /// the value saved before WorkPlot first wrote it. Siri / Apple
    /// Intelligence eligibility keys are deliberately left as they are, so
    /// the device keeps whatever capability it was granted.
    func unspoofDevice() async throws -> ApplyResult {
        guard !isBusy else { throw ApplyError.busy }
        isBusy = true
        defer { isBusy = false }

        let access = MobileGestaltAccess()
        guard (try? access.activate()) != nil else {
            throw ApplyError.activationFailed
        }
        defer { access.deactivate() }

        guard let path = access.mobileGestaltPath else { throw ApplyError.missingPath }
        let url = URL(fileURLWithPath: path)

        let current = try Data(contentsOf: url)

        let hadBackup = backup.hasBackup
        try backup.ensureBackup(from: current)

        guard var plist = try PropertyListSerialization.propertyList(
            from: current, format: nil) as? [String: Any]
        else { throw ApplyError.badPlist }

        var cacheExtra = (plist["CacheExtra"] as? [String: Any]) ?? [:]

        for key in Self.spoofKeys {
            let presenceKey = Self.aiRegionSnapshotPresenceKey(key)
            if defaults.object(forKey: presenceKey) == nil {
                // Never snapshotted, so WorkPlot never wrote it — but the
                // device still reports a spoof, so drop the key entirely.
                cacheExtra.removeValue(forKey: key)
            } else if defaults.bool(forKey: presenceKey) {
                cacheExtra[key] = defaults.object(forKey: Self.aiRegionSnapshotValueKey(key))
            } else {
                cacheExtra.removeValue(forKey: key)
            }
        }

        plist["CacheExtra"] = cacheExtra

        let newData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)

        do {
            try newData.write(to: url, options: [])
        } catch {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeFailed
        }

        guard let readback = try? Data(contentsOf: url), readback == newData else {
            try? backup.restoreData().write(to: url, options: [])
            throw ApplyError.writeVerificationFailed
        }

        let result = ApplyResult(
            appliedCount: 1,
            warnings: [],
            binaryPatchApplied: false,
            backedUpFirstTime: !hadBackup
        )
        lastApply = result
        lastError = nil
        isDeviceSpoofed = false
        return result
    }

    /// Restores the pristine MobileGestalt plist captured on the first apply.
    func restore() async throws -> RestoreResult {
        guard backup.hasBackup else { throw ApplyError.noBackup }
        guard !isBusy else { throw ApplyError.busy }
        isBusy = true
        defer { isBusy = false }

        let access = MobileGestaltAccess()
        guard (try? access.activate()) != nil else {
            throw ApplyError.activationFailed
        }
        defer { access.deactivate() }

        guard let path = access.mobileGestaltPath else { throw ApplyError.missingPath }
        let url = URL(fileURLWithPath: path)

        let pristine = try backup.restoreData()
        do {
            try pristine.write(to: url, options: [])
        } catch {
            throw ApplyError.writeFailed
        }

        guard let readback = try? Data(contentsOf: url), readback == pristine else {
            throw ApplyError.restoreVerificationFailed
        }

        let result = RestoreResult(byteCount: pristine.count)
        lastRestore = result
        lastError = nil
        return result
    }
}
