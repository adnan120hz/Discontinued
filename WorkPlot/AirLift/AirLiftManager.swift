import Foundation
import SwiftUI
import Darwin

// MARK: - Pairing Models

/// AirLift pairing lifecycle: unpaired → pairing → paired.
enum AirLiftPairingState: String {
    case unpaired
    case pairing
    case paired
}

/// A confirmed pairing record (in-app generated code flow, iOS 27).
struct AirLiftPairingRecord: Codable {
    let id: UUID
    let deviceName: String
    let createdAt: Date
    /// The 6-digit code that was displayed and confirmed.
    let code: String
}

/// An imported pairing file (iOS 26 flow: generated on a PC via
/// iDevicePairing / iLoader, then imported here). The file bytes are copied
/// into the app's Documents directory so the original picked URL (which may
/// be security-scoped and transient) is not needed later.
struct AirLiftPairingFile: Codable {
    let name: String
    /// Local path inside the app sandbox (Documents/AirLiftPairing/).
    let storedPath: String
    let importedAt: Date
    let size: Int
}

/// A wallet card the user attached (`.pkpass`) before customizing its image.
struct AirLiftWalletCard: Codable {
    let name: String
    let storedPath: String
    let attachedAt: Date
}

// MARK: - AirLiftManager

/// Coordinates AirLift pairing, pairing-file import, and the wallet-card
/// attachment gate. UI state only — the actual file writes go through
/// `AirLiftFileWriter`.
@MainActor
final class AirLiftManager: ObservableObject {
    static let shared = AirLiftManager()

    @Published var state: AirLiftPairingState = .unpaired
    /// The 6-digit pairing code currently displayed in-app (nil when not pairing).
    @Published var pairingCode: String?
    @Published var pairedRecord: AirLiftPairingRecord?
    @Published var importedFile: AirLiftPairingFile?
    @Published var walletCard: AirLiftWalletCard?
    @Published var statusMessage: String?

    var isPaired: Bool { state == .paired }
    /// Apply buttons in the AirLift theme views bind to this: nothing applies
    /// until the user attaches a wallet card.
    var requiresAttachedCard: Bool { walletCard == nil }

    private let recordKey = "workslop.airlift.pairingRecord"
    private let fileKey = "workslop.airlift.pairingFile"
    private let cardKey = "workslop.airlift.walletCard"

    private init() {
        restore()
    }

    // MARK: Pairing (iOS 27 code flow)

    /// Generates a fresh 6-digit code and moves to `.pairing`.
    /// The code is displayed big in `AirLiftPairingView`; the user confirms
    /// on the device, then taps Confirm Pairing here.
    func startPairing() {
        let digits = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        pairingCode = "\(digits.prefix(3))-\(digits.suffix(3))"
        state = .pairing
        statusMessage = nil
    }

    /// Confirms the displayed code and records the pairing.
    func confirmPairing() {
        guard state == .pairing, let code = pairingCode else {
            statusMessage = "Start pairing first to generate a code."
            return
        }
        let record = AirLiftPairingRecord(
            id: UUID(),
            deviceName: UIDevice.current.name,
            createdAt: Date(),
            code: code
        )
        pairedRecord = record
        state = .paired
        pairingCode = nil
        persist(record, forKey: recordKey)
        statusMessage = "Paired with \(record.deviceName)."
    }

    func cancelPairing() {
        pairingCode = nil
        if state == .pairing { state = .unpaired }
        statusMessage = nil
    }

    func unpair() {
        state = .unpaired
        pairingCode = nil
        pairedRecord = nil
        UserDefaults.standard.removeObject(forKey: recordKey)
        statusMessage = "Unpaired. Pair again to use AirLift writes."
    }

    // MARK: Pairing-file import (iOS 26 flow)

    /// Imports a pairing file picked via the document picker. Copies it into
    /// the app sandbox so the security-scoped source URL isn't needed later.
    func importPairingFile(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let dir = try pairingDirectory()
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let file = AirLiftPairingFile(
                name: url.lastPathComponent,
                storedPath: dest.path,
                importedAt: Date(),
                size: size
            )
            importedFile = file
            persist(file, forKey: fileKey)
            statusMessage = "Pairing file imported: \(file.name)."
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
        statusMessage = "Imported pairing file removed."
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
        pairedRecord = restore(AirLiftPairingRecord.self, forKey: recordKey)
        importedFile = restore(AirLiftPairingFile.self, forKey: fileKey)
        walletCard = restore(AirLiftWalletCard.self, forKey: cardKey)
        // A persisted record means we were paired; the pairing file / card
        // only survive if their stored files still exist.
        if let file = importedFile,
           !FileManager.default.fileExists(atPath: file.storedPath) {
            importedFile = nil
        }
        if let card = walletCard,
           !FileManager.default.fileExists(atPath: card.storedPath) {
            walletCard = nil
        }
        if pairedRecord != nil { state = .paired }
    }

    // MARK: Directories

    private func documentsDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
    }

    private func subdirectory(named name: String) throws -> URL {
        let dir = try documentsDirectory().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        return dir
    }

    private func pairingDirectory() throws -> URL {
        try subdirectory(named: "AirLiftPairing")
    }

    private func walletDirectory() throws -> URL {
        try subdirectory(named: "AirLiftWallet")
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

    /// Throws `VPNError.noActiveVPN` with a user-facing explanation when no
    /// local dev VPN is active. The passcode-theme and wallet-image flows
    /// MUST call this (or check `isVPNActive()`) and block when it throws.
    static func requireVPN() throws {
        guard isVPNActive() else { throw VPNError.noActiveVPN }
    }
}
