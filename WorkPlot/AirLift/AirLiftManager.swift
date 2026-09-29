import Foundation
import SwiftUI
import Darwin
import AirliftFFI

// MARK: - Pairing Models

/// AirLift pairing lifecycle: unpaired → pairing → paired.
enum AirLiftPairingState: String {
    case unpaired
    case pairing
    case paired
}

/// An imported pairing file (iOS 26 flow: generated on a PC via
/// iDevicePairing / iLoader, then imported here — or any existing SideStore /
/// iTunes / AltStore lockdown pairing file dropped into Documents). The file
/// bytes are copied to the canonical in-app path so the original picked URL
/// (which may be security-scoped and transient) is not needed later.
struct AirLiftPairingFile: Codable {
    let name: String
    /// Local path inside the app sandbox (Documents/workslop_pairing.plist).
    let storedPath: String
    let importedAt: Date
    let size: Int
}

/// Pairing-file format, detected from the file's plist keys:
/// - `.rpPairing`: RPPairing credentials (`public_key` + `private_key` +
///   `identifier`) — produced by the in-app Developer Mode pairing (iOS 27).
///   Unlocks the RSD tunnel (RemoteXPC / raw RPPairing) on port 49152.
/// - `.lockdown`: classic lockdown pairing record (`HostCertificate` +
///   `HostID`) — e.g. exported from iDevicePairing / iLoader / SideStore /
///   iTunes / AltStore / Jitterbug. Unlocks lockdownd on port 62078.
/// - `.unknown`: neither — the exploit cannot use it, and import says so.
enum AirLiftPairingFormat {
    case rpPairing
    case lockdown
    case unknown

    var label: String {
        switch self {
        case .rpPairing: return "RPPairing credentials"
        case .lockdown: return "Lockdown pairing record"
        case .unknown: return "Unrecognized format"
        }
    }

    /// Short guidance for what each format unlocks.
    var routeDescription: String {
        switch self {
        case .rpPairing:
            return "RPPairing credentials — unlocks the RSD tunnel (port 49152)."
        case .lockdown:
            return "Lockdown pairing record — unlocks lockdownd (port 62078)."
        case .unknown:
            return "Unrecognized format — AirLift cannot use this file."
        }
    }
}

/// A wallet card the user attached (`.pkpass`) before customizing its image.
struct AirLiftWalletCard: Codable {
    let name: String
    let storedPath: String
    let attachedAt: Date
}

// MARK: - AirLiftManager

/// Coordinates AirLift pairing and the wallet-card attachment gate.
///
/// ## Pairing (genuine on-device RPPairing, iOS 27+)
/// The phone pairs with ITSELF. `startPairing()` runs an RPPairing host
/// (`al_pairing_run_host` from the bundled Rust core — ported from
/// AirCard-iOS, Mak5er, MIT), advertises it over Bonjour as
/// `_remotepairing-pairable-host._tcp.`, and shows the PIN the user must
/// enter in Settings → Privacy & Security → Developer Mode. The pairing
/// file lands in the app's Documents as `workslop_pairing.plist`; an
/// existing SideStore / iTunes / AltStore lockdown pairing file dropped
/// into Documents is auto-discovered and adopted.
///
/// The exploit itself (`AirLiftFileWriter`) then talks to the phone's own
/// services (AFC, streaming_zip_conduit, com.apple.atc) over a loopback
/// tunnel — no Mac involved. iOS 27+ only.
///
/// ## iOS 26.x
/// Manual pairing-file import (file generated on a PC via iLoader /
/// iDevicePairing). Passcode and wallet writes attempt the genuine AirLift
/// exploit on iOS 26 exactly as on iOS 27 — the Rust core detects the
/// pairing format (RPPairing → RSD on 127.0.0.1:49152; lockdown record →
/// lockdownd on :62078) and reports each stage honestly. There is no
/// bad_query fallback in the AirLift path.
@MainActor
final class AirLiftManager: ObservableObject {
    static let shared = AirLiftManager()

    // MARK: RPPairing host identity

    /// Advertised host name. The model is Mac-like so the device's Developer
    /// Mode pairing UI accepts the host (same approach as AirCard-iOS).
    private let hostName = "WorkSlop"
    private let hostModel = "Mac17,7"
    private let bindAddress = "0.0.0.0"

    // MARK: Published state

    @Published var state: AirLiftPairingState = .unpaired
    /// The PIN issued by the RPPairing host — the user enters this in
    /// Settings → Privacy & Security → Developer Mode.
    @Published var pairingPIN: String?
    /// Human-readable pairing progress / result.
    @Published var pairingStatus: String = "Not paired"
    /// Device name reported by the completed handshake (persisted).
    @Published var pairedDeviceName: String?
    @Published var importedFile: AirLiftPairingFile?
    @Published var walletCard: AirLiftWalletCard?
    @Published var statusMessage: String?

    var isPaired: Bool { state == .paired }
    /// Apply buttons in the AirLift theme views bind to this: nothing applies
    /// until the user attaches a wallet card.
    var requiresAttachedCard: Bool { walletCard == nil }

    private var netService: NetService?
    private let localNetwork = AirLiftLocalNetworkAuthorization()
    private let keepAlive = AirLiftKeepAlive()
    private var pairContinuation: CheckedContinuation<String, Error>?

    /// Persisted host altIRK keeps the host identity stable across pairings
    /// so a device that has already paired recognises this host.
    private static let altIRKKey = "workslopPairingHostAltIRK"
    nonisolated private static var storedAltIRK: String {
        get { UserDefaults.standard.string(forKey: altIRKKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: altIRKKey) }
    }

    private let deviceNameKey = "workslop.airlift.pairedDeviceName"
    private let fileKey = "workslop.airlift.pairingFile"
    private let cardKey = "workslop.airlift.walletCard"

    private init() {
        restore()
    }

    // MARK: - Pairing-file discovery

    /// Canonical in-app pairing path.
    nonisolated static func canonicalPairingPath() -> String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workslop_pairing.plist").path
    }

    nonisolated private static func nonEmptyFileSize(at path: String) -> Int {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        return (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    }

    /// Copies the pairing file at `sourcePath` to the canonical path and
    /// returns the canonical path. Returns `sourcePath` unchanged when it
    /// has no readable bytes.
    @discardableResult
    nonisolated static func syncCanonicalPairingFile(from sourcePath: String) -> String {
        let canonical = canonicalPairingPath()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)),
           !data.isEmpty {
            if sourcePath != canonical {
                try? data.write(to: URL(fileURLWithPath: canonical), options: .atomic)
            }
            return canonical
        }
        return sourcePath
    }

    /// Path to the pairing file that was actively found or created.
    /// Checks the canonical path first, then adopts a legacy
    /// `airlift_pairing.plist`, then scans Documents for any
    /// `*.plist` / `*.mobiledevicepairing` / `*.mobilepair` (SideStore,
    /// iTunes, AltStore, Jitterbug exports) and adopts the first non-empty
    /// one.
    nonisolated static func pairingFilePath() -> String {
        let canonical = canonicalPairingPath()
        if nonEmptyFileSize(at: canonical) > 0 { return canonical }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacyNames = ["airlift_pairing.plist", "aircard_pairing.plist"]
        for name in legacyNames {
            let p = dir.appendingPathComponent(name).path
            if nonEmptyFileSize(at: p) > 0 {
                return syncCanonicalPairingFile(from: p)
            }
        }
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for candidate in files where
                candidate.hasSuffix(".plist") ||
                candidate.hasSuffix(".mobiledevicepairing") ||
                candidate.hasSuffix(".mobilepair") {
                let p = dir.appendingPathComponent(candidate).path
                if nonEmptyFileSize(at: p) > 0 {
                    return syncCanonicalPairingFile(from: p)
                }
            }
        }
        return canonical
    }

    /// True when a usable pairing file exists on disk.
    static func hasPairingFile() -> Bool {
        nonEmptyFileSize(at: pairingFilePath()) > 0
    }

    /// Detects the pairing-file format from its plist keys.
    /// RPPairing credentials carry `public_key` + `private_key` + `identifier`;
    /// lockdown records carry `HostCertificate` + `HostID`.
    nonisolated static func detectPairingFormat(at path: String) -> AirLiftPairingFormat {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return .unknown }
        let keys = Set(plist.keys)
        if keys.contains("public_key") && keys.contains("private_key")
            && keys.contains("identifier") {
            return .rpPairing
        }
        if keys.contains("HostCertificate") && keys.contains("HostID") {
            return .lockdown
        }
        return .unknown
    }

    /// Format of the currently active pairing file (nil when unpaired).
    nonisolated static func currentPairingFormat() -> AirLiftPairingFormat? {
        guard hasPairingFile() else { return nil }
        return detectPairingFormat(at: pairingFilePath())
    }

    // MARK: - RPPairing host flow (iOS 27+)

    enum PairingError: LocalizedError {
        case busy
        case localNetworkDenied
        case zeroBytes
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .busy: return "Pairing is already in progress."
            case .localNetworkDenied:
                return "Local Network permission is off. Enable it in Settings › WorkSlop › Local Network."
            case .zeroBytes:
                return "Pairing produced an empty file. Approve the pairing request in Settings, then try again."
            case .failed(let msg): return msg
            }
        }
    }

    /// Starts the RPPairing host. Returns immediately; progress is published
    /// via `pairingStatus` / `pairingPIN` / `state`.
    func startPairing() {
        guard state != .pairing else { return }
        stopAdvertising()
        keepAlive.stopAll()
        state = .pairing
        pairingPIN = nil
        pairingStatus = "Starting local host…"
        statusMessage = nil

        Task {
            _ = await localNetwork.request()
            guard state == .pairing else { return }

            keepAlive.startAudio()
            pairingStatus = "Broadcasting… open Settings to pair"
            runHost()
        }
    }

    /// Async variant: resolves with the pairing-file path, or throws.
    func startAndWait() async throws -> String {
        if state == .pairing {
            cancelPairing()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return try await withCheckedThrowingContinuation { cont in
            pairContinuation = cont
            startPairing()
        }
    }

    /// Cancels an in-progress pairing run.
    func cancelPairing() {
        stopAdvertising()
        keepAlive.stopAll()
        pairingPIN = nil
        if state == .pairing { state = .unpaired }
        pairingStatus = "Cancelled"
        resolve(.failure(CancellationError()))
    }

    /// Unpairs: stops the host and deletes the canonical pairing file so
    /// on-disk state agrees with the UI. The host altIRK is kept, so the
    /// next pairing reuses the same host identity.
    func unpair() {
        stopAdvertising()
        keepAlive.stopAll()
        pairingPIN = nil
        try? FileManager.default.removeItem(atPath: Self.canonicalPairingPath())
        state = .unpaired
        pairedDeviceName = nil
        importedFile = nil
        UserDefaults.standard.removeObject(forKey: deviceNameKey)
        UserDefaults.standard.removeObject(forKey: fileKey)
        pairingStatus = "Not paired"
        statusMessage = "Unpaired. Pair again to use AirLift writes."
    }

    private func resolve(_ result: Result<String, Error>) {
        guard let cont = pairContinuation else { return }
        pairContinuation = nil
        cont.resume(with: result)
    }

    private func runHost() {
        let bind = bindAddress
        let name = hostName
        let model = hostModel
        let outPath = Self.pairingFilePath()
        let altIRK = Self.storedAltIRK
        nonisolated(unsafe) let ctx = UnsafeMutableRawPointer(
            Unmanaged.passRetained(self).toOpaque()
        )

        DispatchQueue.global(qos: .userInitiated).async {
            var result = ALPairResult()
            let rc = bind.withCString { bindC in
                name.withCString { nameC in
                    model.withCString { modelC in
                        outPath.withCString { outC in
                            altIRK.withCString { irkC in
                                al_pairing_run_host(
                                    bindC, 0, nameC, modelC, outC, irkC,
                                    airLiftPairReadyCallback, airLiftPairPinCallback,
                                    ctx, &result)
                            }
                        }
                    }
                }
            }

            let outcome: PairingOutcome
            if rc == 0 {
                let issued = airLiftCStr(result.host_alt_irk_hex)
                if !issued.isEmpty { Self.storedAltIRK = issued }
                let devName = airLiftCStr(result.device_name)
                let filePath = airLiftCStr(result.pairing_file_path)
                outcome = .success(
                    name: devName.isEmpty ? "iPhone" : devName,
                    path: filePath.isEmpty ? outPath : filePath
                )
            } else {
                let msg = airLiftCStr(result.error)
                outcome = .failure(msg.isEmpty ? "pairing failed (rc=\(rc))" : msg)
            }
            al_pairing_result_free(&result)

            DispatchQueue.main.async {
                Unmanaged<AirLiftManager>.fromOpaque(ctx).release()
                self.finish(outcome)
            }
        }
    }

    private enum PairingOutcome {
        case success(name: String, path: String)
        case failure(String)
    }

    private func finish(_ outcome: PairingOutcome) {
        stopAdvertising()
        // Keep the app alive briefly so iOS doesn't suspend it before the
        // user returns from Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.keepAlive.stopAll()
        }
        pairingPIN = nil

        switch outcome {
        case .success(let name, let path):
            let canonical = Self.syncCanonicalPairingFile(from: path)
            let size = Self.nonEmptyFileSize(at: canonical)
            if size == 0 {
                state = .unpaired
                pairingStatus = "Failed: empty pairing file"
                statusMessage = PairingError.zeroBytes.localizedDescription
                resolve(.failure(PairingError.zeroBytes))
            } else {
                state = .paired
                pairedDeviceName = name
                importedFile = nil
                UserDefaults.standard.set(name, forKey: deviceNameKey)
                UserDefaults.standard.removeObject(forKey: fileKey)
                pairingStatus = "Paired: \(name) (\(size) bytes)"
                statusMessage = "Paired with \(name). AirLift writes are unlocked."
                resolve(.success(canonical))
            }
        case .failure(let message):
            state = .unpaired
            pairingStatus = "Failed: \(message)"
            statusMessage = "Pairing failed: \(message)"
            resolve(.failure(PairingError.failed(message)))
        }
    }

    // MARK: Bonjour advertising

    fileprivate func startAdvertising(serviceID: String, port: Int32, txt: [String: Data]) {
        stopAdvertising()
        let service = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: port
        )
        service.setTXTRecord(NetService.data(fromTXTRecord: txt))
        service.publish()
        netService = service
        pairingStatus = "Advertising — open Settings › Privacy & Security › Developer Mode"
    }

    fileprivate func presentPin(_ pin: String) {
        pairingPIN = pin
        pairingStatus = "Enter PIN \(pin) in Settings › Privacy & Security › Developer Mode › Pair with WorkSlop"
    }

    private func stopAdvertising() {
        netService?.stop()
        netService = nil
    }

    // MARK: Pairing-file import (iOS 26 flow + manual alternative)

    /// Imports a pairing file picked via the document picker. Copies it to
    /// the canonical in-app path and marks the device paired.
    func importPairingFile(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                statusMessage = "Import failed: the picked file is empty."
                return
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "plist" || ext == "mobiledevicepairing" || ext == "mobilepair" else {
                statusMessage = "Import failed: \"\(url.lastPathComponent)\" is not a pairing file. " +
                    "Expected .plist or .mobiledevicepairing."
                return
            }
            let canonical = Self.canonicalPairingPath()
            try data.write(to: URL(fileURLWithPath: canonical), options: .atomic)
            let format = Self.detectPairingFormat(at: canonical)
            let file = AirLiftPairingFile(
                name: url.lastPathComponent,
                storedPath: canonical,
                importedAt: Date(),
                size: data.count
            )
            importedFile = file
            pairedDeviceName = nil
            UserDefaults.standard.removeObject(forKey: deviceNameKey)
            persist(file, forKey: fileKey)
            switch format {
            case .rpPairing, .lockdown:
                state = .paired
                pairingStatus = "Paired via imported file (\(format.label), \(data.count) bytes)"
                statusMessage = "Pairing file imported: \(file.name). \(format.routeDescription)"
            case .unknown:
                state = .unpaired
                try? FileManager.default.removeItem(atPath: canonical)
                importedFile = nil
                UserDefaults.standard.removeObject(forKey: fileKey)
                pairingStatus = "Not paired"
                statusMessage = "Import failed: \"\(file.name)\" is not a recognized pairing file " +
                    "(not RPPairing credentials, not a lockdown record). " +
                    "On iOS 27, pair in-app via Developer Mode; on iOS 26, export a pairing file from iDevicePairing or iLoader."
            }
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func removeImportedFile() {
        if let path = importedFile?.storedPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        importedFile = nil
        UserDefaults.standard.removeObject(forKey: fileKey)
        // Also drop any canonical file so the state can't disagree.
        try? FileManager.default.removeItem(atPath: Self.canonicalPairingPath())
        pairedDeviceName = nil
        UserDefaults.standard.removeObject(forKey: deviceNameKey)
        state = .unpaired
        pairingStatus = "Not paired"
        statusMessage = "Pairing file removed."
    }

    // MARK: Wallet card attachment

    /// Attaches a `.pkpass` wallet card; required before the Wallet theme
    /// Apply button enables (`requiresAttachedCard`).
    func attachWalletCard(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let dir = try walletDirectory()
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let card = AirLiftWalletCard(
                name: url.lastPathComponent,
                storedPath: dest.path,
                attachedAt: Date()
            )
            walletCard = card
            persist(card, forKey: cardKey)
            statusMessage = "Wallet card attached: \(card.name)."
        } catch {
            statusMessage = "Attach failed: \(error.localizedDescription)"
        }
    }

    func detachWalletCard() {
        if let path = walletCard?.storedPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        walletCard = nil
        UserDefaults.standard.removeObject(forKey: cardKey)
        statusMessage = "Wallet card detached."
    }

    // MARK: Persistence

    private func persist<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func restore() {
        importedFile = restore(AirLiftPairingFile.self, forKey: fileKey)
        walletCard = restore(AirLiftWalletCard.self, forKey: cardKey)
        pairedDeviceName = UserDefaults.standard.string(forKey: deviceNameKey)
        // A persisted file / card only survives if the file still exists.
        if let file = importedFile {
            if FileManager.default.fileExists(atPath: file.storedPath) {
                // Migrate pre-round-5 imports (Documents/AirLiftPairing/<name>)
                // to the canonical path.
                if file.storedPath != Self.canonicalPairingPath() {
                    let canonical = Self.syncCanonicalPairingFile(from: file.storedPath)
                    if canonical != file.storedPath {
                        let migrated = AirLiftPairingFile(
                            name: file.name, storedPath: canonical,
                            importedAt: file.importedAt, size: file.size)
                        importedFile = migrated
                        persist(migrated, forKey: fileKey)
                    }
                }
            } else {
                importedFile = nil
            }
        }
        if let card = walletCard,
           !FileManager.default.fileExists(atPath: card.storedPath) {
            walletCard = nil
        }
        // Adopt any pairing file already in Documents (from a previous
        // pairing run or a manually dropped SideStore/iTunes export).
        if Self.hasPairingFile() {
            state = .paired
            pairingStatus = pairedDeviceName.map { "Paired: \($0)" }
                ?? importedFile.map { "Paired via imported file (\($0.name))" }
                ?? "Paired"
        } else {
            importedFile = nil
            pairedDeviceName = nil
        }
    }

    // MARK: Directories

    private func documentsDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
    }

    private func walletDirectory() throws -> URL {
        let dir = try documentsDirectory().appendingPathComponent("AirLiftWallet", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - VPNCheck

/// Local dev-VPN detection used to gate the passcode-theme and wallet-image
/// flows. It gates NOTHING else: these are the only two flows that write
/// through a local developer VPN tunnel.
///
/// Implemented with `getifaddrs`, looking for `utun*` interfaces — no extra
/// entitlements or NetworkExtension required. Heuristic, not a guarantee:
/// any active VPN/tunnel interface counts.
///
/// NOTE: this is separate from the AirLift loopback tunnel itself (the
/// exploit connects to 10.7.0.1 / 127.0.0.1 over whatever tunnel interface
/// the loopback VPN app provides). `NetworkStatus` in this folder reports
/// the loopback-tunnel state for the pairing screen.
enum VPNCheck {

    enum VPNError: LocalizedError {
        case noActiveVPN

        var errorDescription: String? {
            "No local dev VPN detected. This theme flow writes " +
            "through a local developer VPN tunnel (utun interface). " +
            "Connect your dev VPN profile, then try again."
        }
    }

    /// True when at least one `utun*` network interface is up.
    static func isVPNActive() -> Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }
        for cursor in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: cursor.pointee.ifa_name)
            if name.hasPrefix("utun") { return true }
        }
        return false
    }

    /// Advisory check: the passcode-theme and wallet-image flows call
    /// `isVPNActive()` and WARN (not block) when no `utun` interface is up.
    /// The exploit always tries `127.0.0.1:49152` first and continues on the
    /// loopback-VPN subnet regardless — a missing VPN only makes the later
    /// targets unreachable. `requireVPN()` is kept for compatibility but
    /// MUST NOT be used to hard-block an apply.
    static func requireVPN() throws {
        guard isVPNActive() else { throw VPNError.noActiveVPN }
    }
}

// MARK: - C callbacks (RPPairing host)

private let airLiftPairReadyCallback: ALPairReadyCb = { ctx, serviceID, port, keys, vals, count in
    guard let ctx = ctx, let serviceID = serviceID else { return }
    let manager = Unmanaged<AirLiftManager>.fromOpaque(ctx).takeUnretainedValue()
    let id = String(cString: serviceID)

    var txt: [String: Data] = [:]
    if let keys = keys, let vals = vals {
        for i in 0..<Int(count) {
            guard let k = keys[i], let v = vals[i] else { continue }
            txt[String(cString: k)] = Data(String(cString: v).utf8)
        }
    }
    DispatchQueue.main.async {
        manager.startAdvertising(serviceID: id, port: Int32(port), txt: txt)
    }
}

private let airLiftPairPinCallback: ALPairPinCb = { pin, ctx in
    guard let ctx = ctx, let pin = pin else { return }
    let manager = Unmanaged<AirLiftManager>.fromOpaque(ctx).takeUnretainedValue()
    let pinString = String(cString: pin)
    DispatchQueue.main.async {
        manager.presentPin(pinString)
    }
}

private func airLiftCStr(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr = ptr else { return "" }
    return String(cString: ptr)
}
