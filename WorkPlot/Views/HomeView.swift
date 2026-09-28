import SwiftUI

/// WorkSlop tweak browser: a single-column capability list under a solid
/// blue status banner. Tapping a row toggles the tweak; tweaks with extra
/// options expand an inline configuration panel under the row.
struct HomeView: View {
    @EnvironmentObject private var store: GestaltStore
    /// `nil` selects "All" — every tweak and tool, uncategorized.
    @State private var category: TweakCategory? = .display
    @State private var configurationID: String?
    @State private var searchText = ""

    private var consoleCategories: [TweakCategory] {
        TweakCategory.allCases.filter { cat in
            cat != .ai &&
            (store.tweaks.contains { $0.category == cat } || toolDefs.contains { $0.category == cat })
        }
    }

    private var selectedTweaks: [Tweak] {
        store.tweaks.filter(\.isEnabled)
    }

    var body: some View {
        NavigationStack {
            Group {
                if DeviceCompatibility.supportsFullFeatureSet {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            statusBanner
                            categoryRail
                            catalog
                            if !selectedTweaks.isEmpty { stagedSection }
                            respringButton
                        }
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                    .searchable(text: $searchText, prompt: "Search tweaks")
                } else {
                    FeatureUnsupportedView(feature: "Tweaks")
                }
            }
            .background(Theme.page)
            .navigationTitle("Tweaks")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Status banner

    private var statusBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            AppMark(name: "ConsoleGlyph", size: 46, tint: .white)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.enabledCount == 0 ? "No changes staged" : "\(store.enabledCount) changes staged")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(store.enabledCount == 0 ? "Pick capabilities below to build your setup." : "Review everything before applying.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            NavigationLink { ApplyChangesView() } label: {
                Label("Review", systemImage: "bolt.horizontal.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.wsBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.white, in: Capsule())
            }
            .disabled(store.enabledCount == 0)
            .opacity(store.enabledCount == 0 ? 0.55 : 1)
        }
        .padding(16)
        .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Theme.wsBlue.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    // MARK: - Category picker

    private var categoryRail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                categoryChip(title: "All", isSelected: category == nil) { category = nil }
                ForEach(consoleCategories) { item in
                    categoryChip(title: item.rawValue, isSelected: category == item) { category = item }
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Theme.pagePadding)
        .padding(.horizontal, Theme.pagePadding)
    }

    private func categoryChip(title: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) {
                select()
                configurationID = nil
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Theme.wsBlue)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(
                    isSelected ? Theme.wsBlue : Theme.card,
                    in: Capsule()
                )
                .overlay(
                    isSelected ? nil :
                        Capsule().stroke(Theme.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catalog

    /// Unified row model so the flat "All" list interleaves tweaks and
    /// tools instead of rendering as two separate groups.
    private enum FlatCell: Identifiable {
        case tweak(Tweak)
        case tool(ToolDef)
        var id: String {
            switch self {
            case .tweak(let t): return t.id
            case .tool(let t): return t.id
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let category {
                let tweaks = store.tweaks.filter { $0.category == category && matchesSearch($0.title) }
                // Tools flow into the same list as the tweaks instead of
                // starting their own group.
                let tools = toolDefs.filter { $0.category == category && $0.id != "respring" && matchesSearch($0.title) }
                let cells = tweaks.map { FlatCell.tweak($0) } + tools.map { FlatCell.tool($0) }
                SectionHeader(category.rawValue, detail: "\(cells.count) available")
                cellList(cells)
            } else {
                let tweaks = store.tweaks.filter { $0.category != .ai && matchesSearch($0.title) }
                let tools = toolDefs.filter { $0.id != "respring" && matchesSearch($0.title) }
                // Interleave tweaks and tools. (A `while` loop can't be used
                // here: result builders don't allow control-flow statements.)
                let cells: [FlatCell] = (0..<max(tweaks.count, tools.count)).reduce(into: []) { acc, i in
                    if i < tweaks.count { acc.append(.tweak(tweaks[i])) }
                    if i < tools.count { acc.append(.tool(tools[i])) }
                }
                SectionHeader("All capabilities", detail: "\(cells.count) available")
                cellList(cells)
            }
        }
    }

    private func matchesSearch(_ title: String) -> Bool {
        searchText.isEmpty || title.localizedCaseInsensitiveContains(searchText)
    }

    /// One solid card holding a divided single-column list. A tweak that is
    /// being configured expands its inline panel directly under its row.
    private func cellList(_ cells: [FlatCell]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                cellRow(cell)
                if let tweak = configuringTweak,
                   case .tweak(let rowTweak) = cell, rowTweak.id == tweak.id,
                   let detail = tweak.detail {
                    InlineTweakConfiguration(tweak: tweak, detail: detail)
                        .padding(.vertical, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if index < cells.count - 1 {
                    Divider().padding(.leading, 58)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .wsCard(cornerRadius: 18)
    }

    @ViewBuilder
    private func cellRow(_ cell: FlatCell) -> some View {
        switch cell {
        case .tweak(let tweak):
            Button { toggle(tweak) } label: {
                HStack(spacing: 14) {
                    Image(systemName: tweak.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            tweak.isEnabled ? Theme.wsBlue : Theme.wsBlue.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tweak.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(tweak.isEnabled && configurationID == tweak.id ? "Configuring" : tweak.subtitle)
                            .font(.caption)
                            .foregroundStyle(tweak.isEnabled ? Theme.wsBlue : .secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: tweak.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(tweak.isEnabled ? Theme.wsBlue : Color(uiColor: .tertiaryLabel))
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tweak.isEnabled ? "Disables this capability" : "Enables this capability")
        case .tool(let tool):
            toolRow(tool)
        }
    }

    @ViewBuilder
    private func toolRow(_ tool: ToolDef) -> some View {
        let label = HStack(spacing: 14) {
            Image(systemName: tool.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Theme.wsBlue.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        if let destination = tool.destination {
            NavigationLink(destination: destination()) { label }
                .buttonStyle(.plain)
        } else if let action = tool.action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        }
    }

    private struct ToolDef: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let category: TweakCategory
        var destination: (() -> AnyView)? = nil
        var action: (() -> Void)? = nil
    }

    private var toolDefs: [ToolDef] {
        [
            ToolDef(id: "carplay", title: "CarPlay Wallpaper", subtitle: "Change the CarPlay wallpaper", symbol: "car", category: .display, destination: { AnyView(CarPlayWallpaperView()) }),
            ToolDef(id: "rdarfix", title: "RDARFix", subtitle: "Edit screen resolution via the canvas exploit", symbol: "wand.and.stars", category: .display, destination: { AnyView(RDARFixView()) }),
            ToolDef(id: "respring", title: "Respring", subtitle: "Restart SpringBoard without rebooting", symbol: "arrow.clockwise", category: .system, action: { RespringHelper.shared.trigger() }),
            ToolDef(id: "gestalteditor", title: "Gestalt Field Editor", subtitle: "Edit cache MobileGestalt", symbol: "slider.horizontal.3", category: .gestalt, destination: { AnyView(GestaltFieldEditorView()) }),
            ToolDef(id: "presetlab", title: "Preset Lab", subtitle: "Build & save Gestalt presets", symbol: "flask", category: .gestalt, destination: { AnyView(PresetLabView()) }),
            ToolDef(id: "sessionlog", title: "Session Log", subtitle: "View exploit session debug logs", symbol: "doc.plaintext", category: .info, destination: { AnyView(SessionLogView()) }),
            ToolDef(id: "updates", title: "Check for Updates", subtitle: "Check for & install updates", symbol: "arrow.down.app", category: .info, destination: { AnyView(UpdateCheckerSheet(showDoneButton: true)) }),
        ]
    }

    // MARK: - Staged changes

    private var stagedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Staged changes", detail: "\(selectedTweaks.count)")
            VStack(spacing: 0) {
                ForEach(Array(selectedTweaks.prefix(4).enumerated()), id: \.element.id) { index, tweak in
                    HStack(spacing: 12) {
                        Image(systemName: tweak.symbol)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(tweak.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.wsBlue)
                    }
                    .padding(.vertical, 9)
                    if index < min(selectedTweaks.count, 4) - 1 {
                        Divider().padding(.leading, 40)
                    }
                }
                if selectedTweaks.count > 4 {
                    Text("+ \(selectedTweaks.count - 4) more changes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Respring

    private var respringButton: some View {
        Button { RespringHelper.shared.trigger() } label: {
            Label("Respring", systemImage: "arrow.clockwise")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.wsBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .wsCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Restart SpringBoard")
    }

    // MARK: - Helpers

    private var configuringTweak: Tweak? {
        guard let configurationID,
              let tweak = store.tweaks.first(where: { $0.id == configurationID }),
              tweak.isEnabled else { return nil }
        return tweak
    }

    private func toggle(_ tweak: Tweak) {
        let willEnable = !tweak.isEnabled
        withAnimation(.snappy) {
            store.setEnabled(willEnable, for: tweak.id)
            configurationID = willEnable && tweak.detail != nil ? tweak.id : nil
        }
    }
}

struct InlineTweakConfiguration: View {
    @EnvironmentObject private var store: GestaltStore
    let tweak: Tweak
    let detail: TweakDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Configure \(tweak.title)")
            switch detail {
            case .picker(let options):
                Picker("Option", selection: store.pickerBinding(for: tweak.id)) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Text(option).tag(index)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 138)
                .wsCard(cornerRadius: 16)
            case .textField(let placeholder, let keyboard):
                TextField(placeholder, text: store.textBinding(for: tweak.id))
                    .keyboardType(keyboard == .numeric ? .numberPad : .default)
                    .textFieldStyle(.roundedBorder)
                    .padding(18)
                    .wsCard(cornerRadius: 16)
            }
            if let note = tweak.notes {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ApplyChangesView: View {
    @EnvironmentObject private var store: GestaltStore
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Review & apply")
                    .font(.largeTitle.weight(.semibold))
                Text("Review staged changes before writing to the MobileGestalt cache.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(store.tweaks.filter(\.isEnabled).enumerated()), id: \.element.id) { index, tweak in
                        HStack(spacing: 12) {
                            Image(systemName: tweak.symbol)
                                .foregroundStyle(Theme.wsBlue)
                                .frame(width: 24)
                            Text(tweak.title)
                                .font(.body.weight(.medium))
                            Spacer()
                        }
                        .padding(.vertical, 11)
                        if index < store.enabledCount - 1 { Divider().padding(.leading, 36) }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .wsCard(cornerRadius: 18)
                ActionButton(title: "Apply \(store.enabledCount) changes", systemImage: "bolt.fill", isBusy: store.isBusy, action: apply)
                Button("Restore pristine backup", role: .destructive) { showRestore = true }
                    .wsAction()
                    .disabled(!store.backup.hasBackup)
            }
            .padding(Theme.pagePadding)
        }
        .background(Theme.page)
        .sheet(isPresented: $showRestore) { RestoreSheet() }
        .alert("Could not apply changes", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func apply() {
        Task {
            do {
                _ = try await store.apply()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                RespringHelper.shared.trigger()
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}
