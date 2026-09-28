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

    // MARK: Destination (NOT device-verified)
    //
    /// Root under which extracted dialer assets are written.
    ///
    /// NOT device-verified: on iOS 26.6–26.7 the Phone app's data container
    /// UUID varies per device. Before shipping, resolve the real container
    /// on-device (list /var/mobile/Containers/Data/Application over the
    /// bad_query lease and match the Phone bundle) and narrow this path.
    /// Until then the flow is reviewable end-to-end but the files land here.
    static let phoneDataContainerPath = "/var/mobile/Containers/Data/Application"

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
            Text("Writes every file to \(Self.phoneDataContainerPath), preserving the zip's folder structure.")
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
            Text("ZIPFoundation extracts stored and deflate entries and verifies CRC32; unsafe paths (zip-slip) are rejected. Destination path is not device-verified yet (see code comment).")
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
            var failures: [String] = []
            for entry in files {
                let dest = (Self.phoneDataContainerPath as NSString)
                    .appendingPathComponent(entry.name)
                do {
                    try AirLiftFileWriter.writeFile(data: entry.data, to: dest)
                } catch {
                    failures.append("\(entry.name): \(error.localizedDescription)")
                }
            }
            let message: String
            if failures.isEmpty {
                message = "Applied \(files.count) files. Respring to take effect."
            } else {
                message = "Failed: \(failures.count) of \(files.count) writes failed. First: \(failures[0])"
            }
            DispatchQueue.main.async {
                status = message
                isApplying = false
            }
        }
    }
}
