import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - ZIP Extraction (ZIPFoundation)
//
// Dialer theme zips are extracted with ZIPFoundation, which is already a
// dependency of the WorkSlop target (see PosterBoardManager's usage).
// Entries are read into memory through Archive's data-based reader;
// ZIPFoundation verifies each entry's CRC32 during extraction, so corrupt
// entries throw instead of staging garbage for writing. Unsafe paths
// (absolute paths or `..` segments — zip-slip) and symlinks are rejected
// before anything is staged.

enum ZipExtractorError: LocalizedError {
    case invalidArchive(String)
    case crcMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let d): return "Not a readable zip archive: \(d)"
        case .crcMismatch(let n): return "CRC32 mismatch for \(n); archive may be corrupt."
        }
    }
}

struct ZipEntry: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let isDirectory: Bool
    var size: Int { data.count }
}

/// Zip-slip guard: rejects absolute paths and `..` segments.
private func sanitizedZipName(_ name: String) -> String? {
    guard !name.isEmpty,
          !name.hasPrefix("/"),
          !name.contains("\\")
    else { return nil }
    let parts = name.split(separator: "/").map(String.init)
    guard !parts.isEmpty, !parts.contains("..") else { return nil }
    return parts.joined(separator: "/")
}

enum ZipExtractor {
    /// Total uncompressed bytes accepted across all entries (zip-bomb guard).
    private static let maxTotalBytes = 200_000_000

    static func extract(_ data: Data) throws -> [ZipEntry] {
        // ZIP magic: files must start with "PK". Rejects garbage uploads
        // before ZIPFoundation can throw a confusing error.
        guard data.count >= 4, data[0] == 0x50, data[1] == 0x4B else {
            throw ZipExtractorError.invalidArchive("missing PK signature")
        }
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw ZipExtractorError.invalidArchive("could not open archive")
        }
        var entries: [ZipEntry] = []
        var totalBytes = 0
        for entry in archive {
            guard entry.type == .file || entry.type == .directory else { continue }
            let isDirectory = entry.type == .directory
            guard let name = sanitizedZipName(entry.path) else { continue }
            var fileData = Data()
            if !isDirectory {
                guard totalBytes + Int(entry.uncompressedSize) <= maxTotalBytes else {
                    throw ZipExtractorError.invalidArchive("archive too large (zip-bomb guard)")
                }
                do {
                    try archive.extract(entry) { chunk in fileData.append(chunk) }
                } catch {
                    throw ZipExtractorError.crcMismatch(entry.path)
                }
                totalBytes += fileData.count
            }
            entries.append(ZipEntry(name: name, data: fileData, isDirectory: isDirectory))
        }
        if entries.isEmpty {
            throw ZipExtractorError.invalidArchive("no entries found")
        }
        return entries
    }
}

// MARK: - Theme Zip Helpers (shared by Dialer / Passcode flows)

/// macOS Finder metadata directory inside zips. These are never real theme
/// assets — writing them fails on-device and pollutes the destination.
private let macOSXPrefix = "__MACOSX/"

/// Prepares extracted zip entries for writing to a theme destination:
/// - Drops `__MACOSX/` metadata entries and directories.
/// - If every file lives under a single top-level folder (e.g.
///   `TelephonyUI-10-cute-cat/`), strips that prefix so assets land directly
///   in the destination (AirCard-iOS writes PNGs flat into TelephonyUI-10).
/// Returns `(relativePath, data)` pairs ready to append to the destination.
func themeWritePairs(from entries: [ZipEntry]) -> [(String, Data)] {
    var files = entries.filter { !$0.isDirectory }
    files.removeAll { $0.name.hasPrefix(macOSXPrefix) || $0.name.contains("/__MACOSX/") }
    guard !files.isEmpty else { return [] }
    // Strip single top-level folder if all files share it.
    let tops = Set(files.map { $0.name.split(separator: "/").first.map(String.init) ?? "" })
    var pairs = files.map { ($0.name, $0.data) }
    if tops.count == 1, let top = tops.first, !top.isEmpty,
       files.allSatisfy({ $0.name.hasPrefix(top + "/") }) {
        let prefix = top + "/"
        pairs = files.map { (String($0.name.dropFirst(prefix.count)), $0.data) }
    }
    // Drop any entries that became empty after stripping.
    return pairs.filter { !$0.0.isEmpty }
}


// MARK: - DialerThemeView

/// "Dialer Theme (iOS 26.6–26.7, bad_query)": import a `.zip` of telephony UI
/// assets, preview the file list, and apply them to the Phone app's data
/// container via `AirLiftFileWriter`.
struct DialerThemeView: View {
    @State private var showPicker = false
    @State private var zipName: String?
    @State private var entries: [ZipEntry] = []
    @State private var status: String?
    @State private var isApplying = false

    // MARK: Destination (per AirCard-iOS)
    //
    /// Dialer theme asset location, per AirCard-iOS
    /// (Mak5er/AirCard-iOS, MIT): telephony UI assets are read by iOS from
    /// `/var/mobile/Library/Caches/TelephonyUI-10` on iOS 18+. The extracted
    /// PNGs are written directly there (single top-level theme folder is
    /// stripped; `__MACOSX/` metadata is skipped).
    static let dialerThemeDestinationPath = "/var/mobile/Library/Caches/TelephonyUI-10"

    private var isSupportedOS: Bool { WorkSlopSupport.legacyPosterBoardAvailable() }
    private var files: [ZipEntry] { entries.filter { !$0.isDirectory } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Dialer Theme (iOS 26.6–26.7, bad_query)")
                if !isSupportedOS {
                    notSupportedCard
                }
                importCard
                if !entries.isEmpty {
                    fileListCard
                    applyCard
                }
                if let status { statusLine(status) }
                infoCard
            }
            .padding(Theme.pagePadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Dialer Theme")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            AirLiftDocumentPicker(
                allowedTypes: [UTType(filenameExtension: "zip") ?? .data],
                onPick: { url in
                    importZip(from: url)
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
        }
    }

    // MARK: Cards

    private var notSupportedCard: some View {
        Text("Dialer theming via bad_query is intended for iOS 26.6–26.7. \(WorkSlopSupport.deviceLabel()). You can still inspect a zip, but Apply is disabled.")
            .font(.footnote)
            .foregroundStyle(Theme.caution)
            .padding(18)
            .background(Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Theme ZIP")
            if let zipName {
                HStack {
                    Image(systemName: "archivebox.fill").foregroundStyle(Theme.accent)
                    Text(zipName).font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text("\(files.count) files").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Import a .zip containing the dialer theme assets. Extraction is done on-device with ZIPFoundation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ActionButton(title: zipName == nil ? "Import Dialer ZIP" : "Replace ZIP",
                         systemImage: "square.and.arrow.down") {
                showPicker = true
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fileListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Files", detail: "\(files.count)")
            ForEach(files.prefix(50)) { entry in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size),
                                                   countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            if files.count > 50 {
                Text("…and \(files.count - 50) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var applyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Apply")
            Text("Writes the theme assets to \(Self.dialerThemeDestinationPath) (per AirCard-iOS).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ActionButton(title: "Apply Dialer Theme",
                         systemImage: "phone.fill",
                         isBusy: isApplying,
                         disabled: !isSupportedOS || files.isEmpty) {
                apply()
            }
            if status?.hasPrefix("Applied") == true {
                Button("Respring to take effect") {
                    RespringHelper.shared.trigger()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Info")
            Text("ZIPFoundation extracts stored and deflate entries and verifies CRC32; unsafe paths (zip-slip) are rejected. Theme assets are written to /var/mobile/Library/Caches/TelephonyUI-10 (per AirCard-iOS); __MACOSX/ metadata entries are skipped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusLine(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(message.hasPrefix("Failed") ? Theme.caution : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func importZip(from url: URL) {
        // Extension check first (case-insensitive): the document picker filters
        // for .zip, but a renamed non-zip file must fail with a clear message.
        guard url.pathExtension.lowercased() == "zip" else {
            entries = []
            zipName = nil
            status = "Failed: \"\(url.lastPathComponent)\" is not a .zip file. " +
                     "Please choose a file ending in .zip."
            return
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            entries = try ZipExtractor.extract(data)
            zipName = url.lastPathComponent
            status = "Extracted \(files.count) files from \(url.lastPathComponent)."
        } catch {
            entries = []
            zipName = nil
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func apply() {
        guard isSupportedOS, !files.isEmpty else { return }
        isApplying = true
        status = nil
        // Off the main thread; AirLiftFileWriter is synchronous file I/O.
        DispatchQueue.global(qos: .userInitiated).async {
            // Per AirCard-iOS: dialer PNGs go to TelephonyUI-10. Skip
            // __MACOSX/ metadata and strip a single top-level theme folder.
            let pairs = themeWritePairs(from: files)
            var failures: [String] = []
            for (relPath, data) in pairs {
                let dest = (Self.dialerThemeDestinationPath as NSString)
                    .appendingPathComponent(relPath)
                do {
                    try AirLiftFileWriter.writeFile(data: data, to: dest)
                } catch {
                    failures.append("\(relPath): \(error.localizedDescription)")
                }
            }
            let message: String
            if failures.isEmpty {
                message = "Applied \(pairs.count) files. Respring to take effect."
            } else {
                message = "Failed: \(failures.count) of \(pairs.count) writes failed. First: \(failures[0])"
            }
            DispatchQueue.main.async {
                status = message
                isApplying = false
            }
        }
    }
}


// MARK: - AirLift Dialer Theme (iOS 27, pairing path)

/// Local availability gate for the AirLift dialer-theme flow.
///
/// Availability for the AirLift dialer theme is resolved by
/// `WorkSlopSupport.airLiftDialerAvailable()` (build-code DB in
/// `WorkSlopBuilds.swift`): iOS 27.0 RC, dev beta 5+, public beta 2+, or
/// official stable. Unknown builds fail open per the shared predicate.
private var airLiftDialerAvailable: Bool { WorkSlopSupport.airLiftDialerAvailable() }

/// "Dialer Theme (AirLift)": the AirLift pairing-path counterpart of
/// `DialerThemeView`. Separate view — the iOS 26.6–26.7 bad_query dialer view
/// above stays as-is.
///
/// Visibility is version-gated: on devices that are NOT iOS 27.0 RC / dev
/// beta 5+ / public beta 2+ / official stable, the view shows a clear
/// "not available on this iOS version" state instead of the import flow.
/// When available, AirLift pairing is required before anything applies.
struct AirLiftDialerThemeView: View {
    @ObservedObject private var manager = AirLiftManager.shared
    @State private var showPicker = false
    @State private var zipName: String?
    @State private var entries: [ZipEntry] = []
    @State private var status: String?
    @State private var isApplying = false

    /// Destination for the AirLift dialer-theme assets, per AirCard-iOS
    /// (Mak5er/AirCard-iOS, MIT): iOS reads telephony UI assets from
    /// `/var/mobile/Library/Caches/TelephonyUI-10` on iOS 18+.
    static let airLiftDialerStagingPath = "/var/mobile/Library/Caches/TelephonyUI-10"

    private var isAvailableVersion: Bool { airLiftDialerAvailable }
    private var files: [ZipEntry] { entries.filter { !$0.isDirectory } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Dialer Theme (AirLift)")
                if !isAvailableVersion {
                    notAvailableCard
                } else if !manager.isPaired {
                    pairingRequiredCard
                } else {
                    importCard
                    if !entries.isEmpty {
                        fileListCard
                        applyCard
                    }
                }
                if let status { statusLine(status) }
                infoCard
            }
            .padding(Theme.pagePadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Dialer Theme (AirLift)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            AirLiftDocumentPicker(
                allowedTypes: [UTType(filenameExtension: "zip") ?? .data],
                onPick: { url in
                    importZip(from: url)
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
        }
    }

    // MARK: Cards

    private var notAvailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "phone.badge.plus")
                    .foregroundStyle(Theme.caution)
                    .font(.title2)
                Text("Not available on this iOS version").font(.headline)
            }
            Text("Dialer theming via AirLift requires iOS 27.0 RC, dev beta 5+, public beta 2+, or the official stable release. This device is \(WorkSlopSupport.deviceLabel()). Nothing can be imported or applied here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pairingRequiredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(Theme.caution)
                    .font(.title2)
                Text("Pairing required").font(.headline)
            }
            Text("AirLift is not paired. Go to AirLift Pairing first — pair this iPhone with itself (iOS 27) or import your pairing file (iOS 26.6–26.7) — then come back.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Theme ZIP")
            if let zipName {
                HStack {
                    Image(systemName: "archivebox.fill").foregroundStyle(Theme.accent)
                    Text(zipName).font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text("\(files.count) files").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Import a .zip containing the dialer theme assets. Extraction is done on-device with ZIPFoundation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ActionButton(title: zipName == nil ? "Import Dialer ZIP" : "Replace ZIP",
                         systemImage: "square.and.arrow.down") {
                showPicker = true
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fileListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Files", detail: "\(files.count)")
            ForEach(files.prefix(50)) { entry in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size),
                                                   countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            if files.count > 50 {
                Text("…and \(files.count - 50) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var applyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Apply")
            Text("Writes every file through AirLift to \(Self.airLiftDialerStagingPath), preserving the zip's folder structure.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ActionButton(title: "Apply Dialer Theme",
                         systemImage: "phone.fill",
                         isBusy: isApplying,
                         disabled: files.isEmpty || !manager.isPaired) {
                apply()
            }
            if status?.hasPrefix("Applied") == true {
                Button("Respring to take effect") {
                    RespringHelper.shared.trigger()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Info")
            Text("This is the AirLift pairing-path dialer theme for iOS 27.0 (RC / dev beta 5+ / public beta 2+ / stable). The separate iOS 26.6–26.7 bad_query dialer view is unchanged. ZIPFoundation extracts with CRC32 verification; zip-slip paths are rejected. Assets are written to /var/mobile/Library/Caches/TelephonyUI-10 (per AirCard-iOS); __MACOSX/ metadata entries are skipped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusLine(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(message.hasPrefix("Failed") ? Theme.caution : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func importZip(from url: URL) {
        guard url.pathExtension.lowercased() == "zip" else {
            entries = []
            zipName = nil
            status = "Failed: \"\(url.lastPathComponent)\" is not a .zip file. " +
                     "Please choose a file ending in .zip."
            return
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            entries = try ZipExtractor.extract(data)
            zipName = url.lastPathComponent
            status = "Extracted \(files.count) files from \(url.lastPathComponent)."
        } catch {
            entries = []
            zipName = nil
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func apply() {
        guard manager.isPaired, !files.isEmpty else { return }
        isApplying = true
        status = nil
        // Off the main thread; AirLiftFileWriter is synchronous file I/O.
        // Group by parent directory: one AirLift sync session per directory
        // instead of one per file (each session replays the full tunnel +
        // Books-sync flow), preserving the zip's folder structure.
        // __MACOSX/ metadata is skipped; a single top-level theme folder
        // is stripped (per AirCard-iOS the PNGs land in TelephonyUI-10).
        DispatchQueue.global(qos: .userInitiated).async {
            let pairs = themeWritePairs(from: files)
            var failures: [String] = []
            var byDirectory: [String: [(name: String, data: Data)]] = [:]
            for (relPath, data) in pairs {
                let parent = ((relPath as NSString).deletingLastPathComponent as NSString)
                    .standardizingPath
                let leaf = (relPath as NSString).lastPathComponent
                byDirectory[parent, default: []].append((name: leaf, data: data))
            }
            for (parent, group) in byDirectory {
                let destDir: String
                if parent.isEmpty || parent == "." {
                    destDir = Self.airLiftDialerStagingPath
                } else {
                    destDir = (Self.airLiftDialerStagingPath as NSString)
                        .appendingPathComponent(parent)
                }
                do {
                    try AirLiftFileWriter.writeFiles(group, toDirectory: destDir)
                } catch {
                    failures.append("\(parent.isEmpty ? "root" : parent): \(error.localizedDescription)")
                }
            }
            let message: String
            if failures.isEmpty {
                message = "Applied \(pairs.count) files in \(byDirectory.count) sync sessions. Respring to take effect."
            } else {
                message = "Failed: \(failures.count) of \(byDirectory.count) directories failed. First: \(failures[0])"
            }
            DispatchQueue.main.async {
                status = message
                isApplying = false
            }
        }
    }
}
