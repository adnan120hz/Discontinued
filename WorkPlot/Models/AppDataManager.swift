import Foundation
import SwiftUI

// MARK: - Models

/// A file or directory entry inside an app-data container.
struct AppDataEntry: Identifiable, Equatable {
    /// Absolute path — unique within a browse session.
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    /// Byte size for files; -1 when unknown or a directory.
    let size: Int64

    /// Lowercased file extension, e.g. "zip".
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
}

/// An app-data container discovered on the device.
struct AppDataContainer: Identifiable, Equatable {
    /// Container UUID — unique.
    let id: String
    let uuid: String
    let bundleId: String?
    let root: String

    var displayName: String { bundleId ?? uuid }
}

// MARK: - Manager

/// Filza-style file browser for iOS app-data containers, backed by the
/// bad_query sandbox escape (`BadQuery` + `BadQueryLeaseScope`).
///
/// Every file-system touch runs inside a short-lived bad_query lease for
/// exactly one operation; the lease is always released, even on failure.
/// Failures surface through `errorMessage` — nothing is faked or silently
/// retried.
///
/// Nothing is listed or read until the user taps Run Access: the access
/// gate performs a real bad_query lease probe and only opens the browser
/// when it succeeds. A rejected probe is reported as an error, never as
/// an empty container list.
///
/// Honest limits:
/// - Only works where `WorkSlopSupport.appDataAvailable()` is true AND the
///   bad_query route resolves on the running build. Everywhere else the UI
///   must show the feature as unavailable, never pretend.
/// - A lease grants access to the requested path subtree only. Some
///   system-protected locations refuse reads/writes even with a lease;
///   those surface as errors, not silent skips.
/// - Modify edits files as UTF-8 text. Binary files cannot be edited
///   in-app and are reported as such instead of being corrupted.
/// - Move is a real filesystem rename (same volume). Import copies bytes
///   from the picked file into the container — the source file is untouched.
/// - Export stages the file into the app's own temp directory and hands it
///   to the share sheet; the copy outside the container is removed when the
///   device clears temp storage.
@MainActor
final class AppDataManager: ObservableObject {

    /// File types accepted for import.
    static let supportedExtensions: Set<String> = [
        "zip", "passthm", "png", "jpg", "jpeg", "img", "raw", "plist",
    ]

    /// Container roots scanned for app-data containers.
    static let containerRoots = [
        "/var/mobile/Containers/Data/Application",
        "/var/mobile/Containers/Data/InternalDaemon",
        "/var/mobile/Containers/Data/PluginKitPlugin",
    ]

    @Published private(set) var containers: [AppDataContainer] = []
    @Published private(set) var activeContainer: AppDataContainer?
    @Published private(set) var currentPath: String = ""
    @Published private(set) var entries: [AppDataEntry] = []
    @Published private(set) var busy = false
    /// True once the user tapped Run Access and a bad_query lease probe
    /// succeeded. The file listing only exists behind this gate.
    @Published private(set) var accessGranted = false
    @Published var status: String = ""
    @Published var errorMessage: String?

    private let fm = FileManager.default

    /// True when the running device can use this feature at all.
    var isAvailable: Bool {
        WorkSlopSupport.appDataAvailable() && BadQuery.isAvailable
    }

    /// Human-readable reason the feature is unavailable, or nil when it is.
    var unavailableReason: String? {
        guard !isAvailable else { return nil }
        if !WorkSlopSupport.appDataAvailable() {
            return "App Data requires iOS 18.x, 26.0 / 26.6.1, or 27.0 dev beta 1–4 / public beta 1–2. This device runs \(WorkSlopSupport.deviceLabel())."
        }
        return "The bad_query sandbox escape did not activate on this build, so app-data containers cannot be read."
    }

    /// Path of the active container root; browsing never escapes above it.
    private var containerRoot: String? { activeContainer?.root }

    /// Path shown in the breadcrumb, relative to the container root.
    var relativePath: String {
        guard let root = containerRoot, currentPath.hasPrefix(root) else { return "/" }
        let rel = String(currentPath.dropFirst(root.count))
        return rel.isEmpty ? "/" : rel
    }

    var canGoUp: Bool {
        guard let root = containerRoot else { return false }
        return currentPath != root && currentPath.hasPrefix(root)
    }

    // MARK: - Access gate

    /// Runs a real bad_query lease probe against the container roots and,
    /// on success, opens the browser. The file listing appears only after
    /// this call succeeds — a failed probe reports an error instead of
    /// showing an empty list.
    func requestAccess() {
        guard isAvailable else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }

        var probeError: String?
        var leaseWorks = false
        for root in Self.containerRoots {
            do {
                let handle = try BadQuery.consume(path: root, create: true)
                handle.release()
                leaseWorks = true
                break
            } catch {
                probeError = error.localizedDescription
            }
        }

        if leaseWorks {
            accessGranted = true
            loadContainers()
        } else {
            errorMessage = "Could not obtain bad_query access to app-data containers"
                + (probeError.map { ": \($0)." } ?? ".")
        }
    }

    // MARK: - Containers

    /// Enumerates app-data containers under the known roots.
    func loadContainers() {
        guard isAvailable, accessGranted else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        var found: [AppDataContainer] = []
        for root in Self.containerRoots {
            let names: [String]
            do {
                names = try BadQuery.list(path: root)
            } catch {
                continue // root not reachable on this device — skip, don't fail
            }
            for name in names {
                let uuid = (name as NSString).lastPathComponent
                guard !uuid.isEmpty, uuid != ".", uuid != ".." else { continue }
                let containerPath = "\(root)/\(uuid)"
                let bundleId = BadQuery.readBundleId(fromContainerPath: containerPath)
                found.append(AppDataContainer(id: uuid, uuid: uuid,
                                              bundleId: bundleId, root: containerPath))
            }
        }
        containers = found.sorted {
            ($0.bundleId ?? $0.uuid).localizedCaseInsensitiveCompare($1.bundleId ?? $1.uuid) == .orderedAscending
        }
        status = found.isEmpty
            ? "No app-data containers found."
            : "\(found.count) container\(found.count == 1 ? "" : "s") found."
    }

    /// Opens a container for browsing.
    func open(_ container: AppDataContainer) {
        activeContainer = container
        errorMessage = nil
        list(path: container.root)
    }

    /// Returns to the container list.
    func closeContainer() {
        activeContainer = nil
        currentPath = ""
        entries = []
        status = ""
        errorMessage = nil
    }

    // MARK: - Browsing

    /// Lists the contents of `path` (must stay inside the container root).
    func list(path: String) {
        guard let root = containerRoot, path.hasPrefix(root) else {
            errorMessage = "Refusing to browse outside the container."
            return
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let listed = try listEntries(at: path)
            currentPath = path
            entries = listed
            status = listed.isEmpty ? "Empty folder." : "\(listed.count) item\(listed.count == 1 ? "" : "s")."
        } catch {
            errorMessage = "Could not list \(path): \(error.localizedDescription)"
        }
    }

    func refresh() {
        guard !currentPath.isEmpty else { return }
        list(path: currentPath)
    }

    /// Moves one level up, staying inside the container root.
    func goUp() {
        guard canGoUp else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        list(path: parent)
    }

    private func listEntries(at path: String) throws -> [AppDataEntry] {
        let names = try BadQueryLeaseScope.withLease(forPath: path) {
            try fm.contentsOfDirectory(atPath: path)
        }
        var result: [AppDataEntry] = []
        try BadQueryLeaseScope.withLease(forPath: path) {
            let ordered = names.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            for name in ordered {
                let child = (path as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: child, isDirectory: &isDir)
                guard exists else { continue }
                var size: Int64 = -1
                if !isDir.boolValue,
                   let attrs = try? fm.attributesOfItem(atPath: child),
                   let s = attrs[.size] as? NSNumber {
                    size = s.int64Value
                }
                result.append(AppDataEntry(id: child, name: name, path: child,
                                           isDirectory: isDir.boolValue, size: size))
            }
        }
        // Directories first, then files, each alphabetical.
        return result.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Move

    /// Moves `entry` into `destinationDir` (inside the same container),
    /// optionally renaming it. Real filesystem rename — no copies left behind.
    func move(_ entry: AppDataEntry, to destinationDir: String, newName: String? = nil) {
        guard let root = containerRoot,
              entry.path.hasPrefix(root), destinationDir.hasPrefix(root) else {
            errorMessage = "Move is only allowed inside the open container."
            return
        }
        let trimmed = (newName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? entry.name : trimmed
        guard !finalName.contains("/") else {
            errorMessage = "The new name must not contain \"/\"."
            return
        }
        let destPath = (destinationDir as NSString).appendingPathComponent(finalName)
        guard destPath != entry.path else {
            errorMessage = "Source and destination are the same."
            return
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try BadQueryLeaseScope.withLease(forPath: root) {
                if fm.fileExists(atPath: destPath) {
                    throw NSError(domain: "AppDataManager", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "\"\(finalName)\" already exists in the destination."
                    ])
                }
                try fm.moveItem(atPath: entry.path, toPath: destPath)
            }
            status = "Moved \"\(entry.name)\" → \(relativeDisplayPath(destPath))."
            list(path: currentPath)
        } catch {
            errorMessage = "Move failed: \(error.localizedDescription)"
        }
    }

    // MARK: - New folder

    /// Creates a folder inside the current directory.
    func createFolder(named name: String) {
        guard let root = containerRoot, !currentPath.isEmpty, currentPath.hasPrefix(root) else {
            errorMessage = "Open a container folder before creating folders."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Folder name cannot be empty."
            return
        }
        guard !trimmed.contains("/") else {
            errorMessage = "The folder name must not contain \"/\"."
            return
        }
        let dest = (currentPath as NSString).appendingPathComponent(trimmed)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try BadQueryLeaseScope.withLease(forPath: root) {
                try fm.createDirectory(atPath: dest, withIntermediateDirectories: false)
            }
            status = "Created folder \"\(trimmed)\"."
            list(path: currentPath)
        } catch {
            errorMessage = "Could not create folder: \(error.localizedDescription)"
        }
    }

    // MARK: - View / Modify (text)

    /// Reads a file's raw bytes under a lease, for preview use.
    func readFileData(_ entry: AppDataEntry) -> Data? {
        guard let root = containerRoot, !entry.isDirectory, entry.path.hasPrefix(root) else {
            errorMessage = "Only files inside the open container can be read."
            return nil
        }
        do {
            return try BadQueryLeaseScope.withLease(forPath: root) {
                try Data(contentsOf: URL(fileURLWithPath: entry.path))
            }
        } catch {
            errorMessage = "Could not read \"\(entry.name)\": \(error.localizedDescription)"
            return nil
        }
    }

    /// Reads a file as UTF-8 text. Returns nil — with a clear message — for
    /// binary files, which cannot be edited in-app.
    func readTextFile(_ entry: AppDataEntry) -> String? {
        guard let data = readFileData(entry) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else {
            errorMessage = "\"\(entry.name)\" is binary and cannot be edited as text."
            return nil
        }
        return text
    }

    /// Overwrites a file with UTF-8 text under a lease.
    func writeTextFile(_ text: String, to entry: AppDataEntry) {
        guard let root = containerRoot, !entry.isDirectory, entry.path.hasPrefix(root) else {
            errorMessage = "Only files inside the open container can be modified."
            return
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try BadQueryLeaseScope.withLease(forPath: root) {
                try text.write(toFile: entry.path, atomically: true, encoding: .utf8)
            }
            status = "Saved \"\(entry.name)\"."
            list(path: currentPath)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    /// Stages a file into the app's own temp directory under a lease and
    /// returns the staged URL for the share sheet. Returns nil on failure.
    func exportFile(_ entry: AppDataEntry) -> URL? {
        guard let root = containerRoot, !entry.isDirectory, entry.path.hasPrefix(root) else {
            errorMessage = "Only files can be exported."
            return nil
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let exportDir = fm.temporaryDirectory.appendingPathComponent("appdata-export", isDirectory: true)
            try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
            let destURL = exportDir.appendingPathComponent(entry.name)
            try BadQueryLeaseScope.withLease(forPath: root) {
                let data = try Data(contentsOf: URL(fileURLWithPath: entry.path))
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try data.write(to: destURL)
            }
            status = "Staged \"\(entry.name)\" for export."
            return destURL
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Add (import)

    /// Copies a file picked by the user into the current directory.
    /// Only ``supportedExtensions`` are accepted; anything else is rejected
    /// with a clear message instead of being silently converted.
    func addFile(from sourceURL: URL) {
        guard let root = containerRoot, !currentPath.isEmpty, currentPath.hasPrefix(root) else {
            errorMessage = "Open a container folder before adding files."
            return
        }
        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            errorMessage = "\"\(sourceURL.lastPathComponent)\" is not a supported type. Supported: \(Self.supportedExtensions.sorted().joined(separator: ", "))."
            return
        }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        let destPath = (currentPath as NSString).appendingPathComponent(sourceURL.lastPathComponent)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try BadQueryLeaseScope.withLease(forPath: root) {
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(atPath: destPath)
                }
                try fm.copyItem(at: sourceURL, to: URL(fileURLWithPath: destPath))
            }
            status = "Added \"\(sourceURL.lastPathComponent)\" to \(relativeDisplayPath(currentPath))."
            list(path: currentPath)
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func relativeDisplayPath(_ path: String) -> String {
        guard let root = containerRoot, path.hasPrefix(root) else { return path }
        let rel = String(path.dropFirst(root.count))
        return rel.isEmpty ? "/" : rel
    }

    static func formatSize(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
