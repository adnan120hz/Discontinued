import SwiftUI

/// WorkSlop tweak browser.
///
/// Layout: a single-column capability list under a slim status strip. In
/// portrait the section menu lives in a floating box anchored to the
/// middle-right edge — items stack downward and labels wrap instead of
/// truncating. In landscape the menu becomes a horizontal chip rail above
/// the list. Tapping a row toggles the tweak; tweaks with extra options
/// expand an inline configuration panel under the row.
struct HomeView: View {
    @EnvironmentObject private var store: GestaltStore
    /// `nil` selects "All" — every tweak and tool, uncategorized.
    @State private var category: TweakCategory? = .display
    @State private var configurationID: String?
    @State private var searchText = ""

    /// Floating menu geometry (portrait). Content reserves this much
    /// trailing space so nothing ever slides underneath the menu.
    private let menuWidth: CGFloat = 148
    private let menuTrailing: CGFloat = 10
    private let menuGap: CGFloat = 8
    private var menuClearance: CGFloat { menuWidth + menuTrailing + menuGap }

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
                // All tweaks always visible; unsupported ones are grayed/locked.
                // (Per user request: no more full-screen "Unsupported" gate.)
                if true {
                    GeometryReader { geo in
                        let portrait = geo.size.height >= geo.size.width
                        ZStack {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    statusStrip
                                    if !portrait { categoryRail }
                                    catalog
                                    if !selectedTweaks.isEmpty { stagedSection }
                                    respringButton
                                }
                                .padding(.horizontal, Theme.pagePadding)
                                .padding(.trailing, portrait ? menuClearance - Theme.pagePadding : 0)
                                .padding(.bottom, 32)
                            }
                            .scrollIndicators(.hidden)
                            if portrait {
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    floatingMenu
                                }
                                .padding(.trailing, menuTrailing)
                            }
                        }
                    }
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

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: store.enabledCount == 0 ? "square.stack.3d.up" : "square.stack.3d.up.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(stagedTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(store.enabledCount == 0 ? "Pick capabilities below to build your setup." : "Review everything before applying.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            NavigationLink { ApplyChangesView() } label: {
                Text("Review")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Theme.wsBlue, in: Capsule())
            }
            .disabled(store.enabledCount == 0)
            .opacity(store.enabledCount == 0 ? 0.4 : 1)
        }
        .padding(14)
        .wsCard(cornerRadius: 18)
    }

    private var stagedTitle: String {
        switch store.enabledCount {
        case 0: return "No changes staged"
        case 1: return "1 change staged"
        default: return "\(store.enabledCount) changes staged"
        }
    }

    // MARK: - Floating section menu (portrait)

    /// SF Symbol per section, shown next to the label in the floating menu.
    private func symbol(for category: TweakCategory) -> String {
        switch category {
        case .display: return "display"
        case .device: return "iphone"
        case .system: return "gearshape"
        case .liquidGlass: return "drop"
        case .ipad: return "ipad"
        case .gestalt: return "slider.horizontal.3"
        case .info: return "info.circle"
        case .ai: return "brain.head.profile"
        }
    }

    /// Floating box anchored middle-right. Items stack downward; labels
    /// wrap onto multiple lines and are never truncated.
    private var floatingMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sections")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 4)
            menuItem(title: "All", symbol: "square.grid.2x2", isSelected: category == nil) {
                category = nil
            }
            ForEach(consoleCategories) { item in
                menuItem(title: item.rawValue, symbol: symbol(for: item), isSelected: category == item) {
                    category = item
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: menuWidth, alignment: .leading)
        .wsFloat(cornerRadius: 18)
    }

    private func menuItem(title: String, symbol: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) {
                select()
                configurationID = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Theme.wsBlue)
                    .frame(width: 20)
                // No lineLimit: the label wraps instead of truncating.
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
            }
            .frame(minWidth: 116, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isSelected ? Theme.wsBlue : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Category rail (landscape)

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
                    Divider().padding(.leading, 54)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .wsCard(cornerRadius: 18)
    }

    @ViewBuilder
    private func cellRow(_ cell: FlatCell) -> some View {
        switch cell {
        case .tweak(let tweak):
            let supported = tweak.isSupportedOnCurrentOS()
            Button { toggle(tweak) } label: {
                HStack(spacing: 12) {
                    Image(systemName: supported ? tweak.symbol : "lock.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            !supported ? Color.gray.opacity(0.4) :
                            tweak.isEnabled ? Theme.wsBlue : Theme.wsBlue.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        // Titles wrap (up to two lines) instead of
                        // truncating mid-word.
                        Text(tweak.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(supported ? .primary : .secondary)
                            .lineLimit(2)
                        Text(!supported ? "Requires \(tweak.minIOS ?? "?")+" :
                             tweak.isEnabled && configurationID == tweak.id ? "Configuring" : tweak.subtitle)
                            .font(.caption)
                            .foregroundStyle(!supported ? .secondary :
                                             tweak.isEnabled ? Theme.wsBlue : .secondary)
                            .lineLimit(2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Image(systemName: !supported ? "lock.fill" :
                          tweak.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(!supported ? Color.gray :
                                         tweak.isEnabled ? Theme.wsBlue : Color(uiColor: .tertiaryLabel))
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .opacity(supported ? 1.0 : 0.6)
            }
            .buttonStyle(.plain)
            .disabled(!supported)
            .accessibilityHint(!supported ? "Not supported on this iOS version" :
                              tweak.isEnabled ? "Disables this capability" : "Enables this capability")
        case .tool(let tool):
            toolRow(tool)
        }
    }

    @ViewBuilder
    private func toolRow(_ tool: ToolDef) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: tool.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.wsBlue.opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
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
            ToolDef(id: "lgapply", title: "Disable Liquid Glass", subtitle: "Backup-safe apply flow", symbol: "drop.fill", category: .liquidGlass, destination: { AnyView(LiquidGlassApplyView()) }),
            ToolDef(id: "appdata", title: "App Data", subtitle: "Browse and manage app data files", symbol: "folder", category: .system, destination: { AnyView(AppDataView()) }),
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
                            .frame(width: 30, height: 30)
                            .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(tweak.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.wsBlue)
                    }
                    .padding(.vertical, 9)
                    if index < min(selectedTweaks.count, 4) - 1 {
                        Divider().padding(.leading, 42)
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
            .padding(.horizontal, 14)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Respring

    private var respringButton: some View {
        Button { RespringHelper.shared.trigger() } label: {
            Label("Respring", systemImage: "arrow.clockwise")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .wsAction()
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
        // Locked tweaks cannot be enabled on unsupported iOS.
        guard tweak.isSupportedOnCurrentOS() else { return }
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
                .wsCard(cornerRadius: 14)
            case .textField(let placeholder, let keyboard):
                TextField(placeholder, text: store.textBinding(for: tweak.id))
                    .keyboardType(keyboard == .numeric ? .numberPad : .default)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .wsCard(cornerRadius: 14)
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Review staged changes before writing to the MobileGestalt cache.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(store.tweaks.filter(\.isEnabled).enumerated()), id: \.element.id) { index, tweak in
                        HStack(spacing: 12) {
                            Image(systemName: tweak.symbol)
                                .foregroundStyle(Theme.wsBlue)
                                .frame(width: 24)
                            Text(tweak.title)
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                            Spacer(minLength: 6)
                        }
                        .padding(.vertical, 11)
                        if index < store.enabledCount - 1 { Divider().padding(.leading, 36) }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .wsCard(cornerRadius: 18)
                ActionButton(title: "Apply \(store.enabledCount) changes", systemImage: "bolt.fill", isBusy: store.isBusy, action: apply)
                Button("Restore pristine backup", role: .destructive) { showRestore = true }
                    .wsAction()
                    .disabled(!store.backup.hasBackup)
            }
            .padding(Theme.pagePadding)
        }
        .background(Theme.page)
        .navigationTitle("Review & Apply")
        .navigationBarTitleDisplayMode(.large)
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
