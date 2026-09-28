import SwiftUI
import UniformTypeIdentifiers

/// Filza-style app-data browser: browse app containers on the device and
/// view, modify, move, add, import, and export files — all through the
/// bad_query sandbox escape (`AppDataManager`).
///
/// Nothing is listed until the user taps **Run Access**, which performs a
/// real bad_query lease probe; a failed probe reports an error instead of
/// showing an empty list.
///
/// Supported on iOS 18.x, 26.0 / 26.6.1, and 27.0 dev beta 1–4 /
/// public beta 1–2. On other builds the view explains why it is unavailable
/// instead of pretending to work.
///
/// This is a standalone view; the coordinator embeds it into the menu.
public struct AppDataView: View {
    @StateObject private var manager = AppDataManager()
    @State private var searchText = ""
    @State private var selectedEntry: AppDataEntry?
    @State private var moveEntry: AppDataEntry?
    @State private var moveNewName = ""
    @State private var showingImporter = false
    @State private var showingAddMenu = false
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var viewingEntry: AppDataEntry?
    @State private var editingEntry: AppDataEntry?
    @State private var editorText = ""
    @State private var shareURL: URL?
    @State private var isSharing = false

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
        for ext in ["passthm", "img", "raw", "plist"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let reason = manager.unavailableReason {
                unavailableCard(reason: reason)
            } else if !manager.accessGranted {
                runAccessCard
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
        .confirmationDialog("Add", isPresented: $showingAddMenu, titleVisibility: .visible) {
            Button("New Folder") {
                newFolderName = ""
                showingNewFolder = true
            }
            Button("Import File") {
                selectedEntry = nil
                showingImporter = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $viewingEntry) { entry in
            AppDataFileViewer(entry: entry, manager: manager)
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                TextEditor(text: $editorText)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .navigationTitle(entry.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editingEntry = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                manager.writeTextFile(editorText, to: entry)
                                editingEntry = nil
                                selectedEntry = nil
                            }
                            .disabled(manager.busy)
                        }
                    }
            }
        }
        .sheet(isPresented: $showingNewFolder) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Folder name", text: $newFolderName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .wsCard(cornerRadius: 12)
                    Spacer()
                }
                .padding()
                .navigationTitle("New Folder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingNewFolder = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            manager.createFolder(named: newFolderName)
                            showingNewFolder = false
                        }
                        .disabled(manager.busy || newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isSharing) {
            if let url = shareURL {
                ActivityShareSheet(items: [url])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Data")
                .font(.title2.weight(.semibold))
            Text("Filza-style browser for app-data containers, via the bad_query sandbox escape.")
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

    // MARK: - Run Access gate

    private var runAccessCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.wsBlue)
                Text("App Data Access")
                    .font(.title3.weight(.semibold))
                Text("Tap Run Access to open a bad_query sandbox lease and scan app-data containers on this device. Nothing is listed until access is granted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if manager.busy {
                    ProgressView("Requesting access…")
                        .padding(.top, 4)
                } else {
                    Button("Run Access") { manager.requestAccess() }
                        .wsAction(prominent: true)
                        .padding(.top, 4)
                }

                if let error = manager.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.destructive)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Supported: iOS 18.x, 26.0 / 26.6.1, 27.0 dev beta 1–4 / public beta 1–2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 24)
        }
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
            toolbar
            entriesList
            actionArea
            statusLine
        }
    }

    private var toolbar: some View {
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

            Button { showingAddMenu = true } label: {
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
                Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(for: entry))
                    .foregroundStyle(entry.isDirectory ? Theme.wsBlue : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if entry.isDirectory {
                            EmptyView()
                        } else {
                            typeBadge(for: entry)
                        }
                    }
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

    // MARK: - File type icons & badges

    private func fileIcon(for entry: AppDataEntry) -> String {
        switch entry.fileExtension {
        case "zip": return "archivebox.fill"
        case "png", "jpg", "jpeg", "img": return "photo.fill"
        case "raw": return "camera.fill"
        case "plist": return "list.bullet.rectangle.fill"
        case "passthm": return "key.fill"
        default: return "doc.fill"
        }
    }

    @ViewBuilder
    private func typeBadge(for entry: AppDataEntry) -> some View {
        if entry.isDirectory {
            EmptyView()
        } else if let label = badgeLabel(for: entry.fileExtension) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(badgeColor(for: entry.fileExtension))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor(for: entry.fileExtension).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            EmptyView()
        }
    }

    private func badgeLabel(for ext: String) -> String? {
        switch ext {
        case "zip": return "ZIP"
        case "passthm": return "PSTHM"
        case "png": return "PNG"
        case "jpg", "jpeg": return "JPEG"
        case "img": return "IMG"
        case "raw": return "RAW"
        case "plist": return "PLIST"
        default: return nil
        }
    }

    private func badgeColor(for ext: String) -> Color {
        switch ext {
        case "zip": return .orange
        case "passthm": return .purple
        case "png", "jpg", "jpeg": return .green
        case "img": return .teal
        case "raw": return .pink
        case "plist": return Theme.wsBlue
        default: return .secondary
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
            HStack(spacing: 8) {
                Button { viewingEntry = entry } label: {
                    Label("View", systemImage: "eye")
                }
                .wsAction()
                .disabled(manager.busy)

                Button {
                    if let text = manager.readTextFile(entry) {
                        editorText = text
                        editingEntry = entry
                    }
                } label: {
                    Label("Modify", systemImage: "pencil")
                }
                .wsAction()
                .disabled(manager.busy)

                Button {
                    if let url = manager.exportFile(entry) {
                        shareURL = url
                        isSharing = true
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .wsAction()
                .disabled(manager.busy)
            }
            HStack(spacing: 8) {
                Button {
                    moveEntry = entry
                    moveNewName = entry.name
                    selectedEntry = nil
                } label: {
                    Label("Move…", systemImage: "folder.badge.plus")
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
        Text("Reads, moves, and imports go through the bad_query sandbox escape. Only zip, passthm, png, jpeg, img, raw, and plist files can be imported. Text editing works on UTF-8 text files only — binary files cannot be edited in-app. Some protected locations may refuse access even with an active lease.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - File viewer

/// Shows a text preview (UTF-8 files), an image preview (image files), or
/// an honest note when the format cannot be previewed.
private struct AppDataFileViewer: View {
    let entry: AppDataEntry
    let manager: AppDataManager
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var image: UIImage?
    @State private var loaded = false

    private var isImage: Bool {
        ["png", "jpg", "jpeg", "img"].contains(entry.fileExtension)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView("Reading file…")
                } else if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                } else if let text {
                    ScrollView {
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Preview is not available for this format.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Use Export to copy the file out and inspect it elsewhere.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        if isImage {
            if let data = manager.readFileData(entry) {
                image = UIImage(data: data)
            }
        } else {
            // readTextFile reports a clear message for binary files.
            text = manager.readTextFile(entry)
        }
        loaded = true
    }
}
