import SwiftUI
import UniformTypeIdentifiers

/// App Data reader: browse app-data containers on the device, move files
/// between folders, and import files — all through the bad_query sandbox
/// escape (`AppDataManager`).
///
/// Supported on iOS 18.x, 26.0 / 26.6.1, and 27.0 dev beta 1–4 /
/// public beta 1–2. On other builds the view explains why it is unavailable
/// instead of pretending to work.
///
/// The coordinator wires this view into the menu; it is intentionally not
/// referenced from `HomeView` here.
public struct AppDataView: View {
    @StateObject private var manager = AppDataManager()
    @State private var searchText = ""
    @State private var selectedEntry: AppDataEntry?
    @State private var moveEntry: AppDataEntry?
    @State private var moveNewName = ""
    @State private var showingImporter = false

    public init() {}

    private var filteredContainers: [AppDataContainer] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return manager.containers }
        return manager.containers.filter {
            $0.displayName.lowercased().contains(q) || $0.uuid.lowercased().contains(q)
        }
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.zip, .png, .jpeg]
        for ext in ["passthm", "raw"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let reason = manager.unavailableReason {
                unavailableCard(reason: reason)
            } else if manager.activeContainer == nil {
                containerList
            } else {
                browser
            }

            Spacer(minLength: 0)
            limitsFootnote
        }
        .padding(Theme.pagePadding)
        .background(Theme.page)
        .onAppear {
            if manager.containers.isEmpty && manager.isAvailable {
                manager.loadContainers()
            }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { manager.addFile(from: url) }
            case .failure(let error):
                manager.errorMessage = "Could not pick a file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Data")
                .font(.title2.weight(.semibold))
            Text("Browse app-data containers, move files, and import files via bad_query.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Unavailable

    private func unavailableCard(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.caution)
                Text("Not available on this device")
                    .font(.headline)
            }
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Supported: iOS 18.x, 26.0 / 26.6.1, 27.0 dev beta 1–4 / public beta 1–2.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .wsCard()
    }

    // MARK: - Container list

    private var containerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by bundle ID or UUID", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .wsCard(cornerRadius: 14)

                Button { manager.loadContainers() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.wsBlue)
                .wsCard(cornerRadius: 14)
                .disabled(manager.busy)
            }

            if manager.busy && manager.containers.isEmpty {
                ProgressView("Scanning containers…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            } else if filteredContainers.isEmpty {
                Text(manager.containers.isEmpty
                     ? "No containers found. Tap Reload to scan again."
                     : "No containers match \"\(searchText)\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredContainers) { container in
                            Button { manager.open(container) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "app.dashed")
                                        .foregroundStyle(Theme.wsBlue)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(container.bundleId ?? "Unknown app")
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                        Text(container.uuid)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .wsCard(cornerRadius: 14)
                        }
                    }
                }
            }

            statusLine
        }
    }

    // MARK: - Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 12) {
            breadcrumbBar
            entriesList
            actionArea
            statusLine
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 8) {
            Button {
                selectedEntry = nil
                if manager.canGoUp { manager.goUp() } else { manager.closeContainer() }
            } label: {
                Image(systemName: manager.canGoUp ? "chevron.left" : "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.wsBlue)
            .wsCard(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.activeContainer?.displayName ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(manager.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                selectedEntry = nil
                manager.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.wsBlue)
            .wsCard(cornerRadius: 12)
            .disabled(manager.busy)

            Button {
                selectedEntry = nil
                showingImporter = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(manager.busy)
        }
    }

    private var entriesList: some View {
        Group {
            if manager.busy && manager.entries.isEmpty {
                ProgressView("Reading folder…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if manager.entries.isEmpty {
                Text("This folder is empty.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: AppDataEntry) -> some View {
        let isSelected = selectedEntry?.id == entry.id
        return Button {
            if entry.isDirectory {
                selectedEntry = nil
                manager.list(path: entry.path)
            } else if moveEntry == nil {
                selectedEntry = isSelected ? nil : entry
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(for: entry.name))
                    .foregroundStyle(entry.isDirectory ? Theme.wsBlue : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.isDirectory ? "Folder" : AppDataManager.formatSize(entry.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.wsBlue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .wsCard(cornerRadius: 14)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.wsBlue, lineWidth: 2)
            }
        }
    }

    private func fileIcon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "zip": "archivebox.fill"
        case "png", "jpg", "jpeg": "photo.fill"
        case "passthm": "key.fill"
        default: "doc.fill"
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionArea: some View {
        if let moving = moveEntry {
            moveBar(moving)
        } else if let selected = selectedEntry, !selected.isDirectory {
            selectedFileBar(selected)
        }
    }

    private func selectedFileBar(_ entry: AppDataEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(AppDataManager.formatSize(entry.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Move…") {
                    moveEntry = entry
                    moveNewName = entry.name
                    selectedEntry = nil
                }
                .wsAction(prominent: true)
                .disabled(manager.busy)
                Spacer()
                Button("Deselect") { selectedEntry = nil }
                    .wsAction()
            }
        }
        .padding(14)
        .wsCard()
    }

    private func moveBar(_ entry: AppDataEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(Theme.wsBlue)
                Text("Moving \"\(entry.name)\" — navigate to the destination folder, optionally rename, then tap Move here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            TextField("File name", text: $moveNewName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                Button("Move here") {
                    manager.move(entry, to: manager.currentPath, newName: moveNewName)
                    moveEntry = nil
                }
                .wsAction(prominent: true)
                .disabled(manager.busy || moveNewName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Cancel") { moveEntry = nil }
                    .wsAction()
            }
        }
        .padding(14)
        .wsCard()
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            if manager.busy {
                ProgressView().scaleEffect(0.8)
            }
            if let error = manager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.destructive)
            } else if !manager.status.isEmpty {
                Text(manager.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var limitsFootnote: some View {
        Text("Reads, moves, and imports go through the bad_query sandbox escape. Some protected locations may refuse access even with an active lease. Supported import types: zip, passthm, png, jpeg, raw.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
