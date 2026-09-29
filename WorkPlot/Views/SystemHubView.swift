import SwiftUI
import UIKit

/// WorkSlop settings hub: a blue identity banner up top, backup status and
/// tool shortcuts as divided list cards, then credits and thanks.
struct SystemHubView: View {
    @EnvironmentObject private var store: GestaltStore
    @State private var showRestore = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identityBanner
                    statusCard
                    toolsSection
                    credits
                    attributions
                    thanks
                }
                .padding(Theme.pagePadding)
            }
            .scrollIndicators(.hidden)
            .background(Theme.page)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showRestore) { RestoreSheet() }
    }

    // MARK: - Identity & status

    private var identityBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white.opacity(0.5), lineWidth: 1.5)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("WorkSlop")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("iOS system modification tools • beta 1")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(18)
        .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Theme.wsBlue.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Device access")
            HStack(spacing: 14) {
                Image(systemName: store.backup.hasBackup ? "checkmark.shield.fill" : "shield")
                    .foregroundStyle(store.backup.hasBackup ? Theme.affirmative : Theme.wsBlue)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Theme.wsBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.backup.hasBackup ? "Backup is available" : "No backup has been created")
                        .font(.subheadline.weight(.semibold))
                    Text(store.backup.hasBackup ? "Your recovery point is safe." : "One is created automatically on first apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Tools")
            VStack(spacing: 0) {
                Button { showRestore = true } label: {
                    toolRow(
                        title: "Recovery",
                        detail: store.backup.hasBackup ? "Restore the pristine MobileGestalt backup" : "A backup is created on first apply",
                        symbol: "arrow.uturn.backward"
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 58)
                NavigationLink { SettingsView() } label: {
                    toolRow(
                        title: "Preferences",
                        detail: "PosterBoard access, appearance and backups",
                        symbol: "paintbrush"
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 58)
                NavigationLink { OnboardingView() } label: {
                    toolRow(
                        title: "Tutorial",
                        detail: "Replay the first-launch walkthrough",
                        symbol: "book"
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 58)
                NavigationLink { GestaltBackupFileView() } label: {
                    toolRow(
                        title: "Mobile Gestalt Backup File",
                        detail: "Create, import and restore MobileGestalt backups (.plist)",
                        symbol: "externaldrive.fill"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .wsCard(cornerRadius: 18)
        }
    }

    private func toolRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - Credits

    private var credits: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Credits")
            VStack(spacing: 0) {
                credit("Adnan.120hz", "Owner", "https://github.com/adnan120hz")
                Divider().padding(.leading, 16)
                creditDual(
                    name: "Adnan.120hz & Gievano",
                    role: "WorkPlot Based apps development",
                    links: [
                        ("github.com/adnan120hz", "https://github.com/adnan120hz"),
                        ("github.com/gievano", "https://github.com/gievano"),
                    ]
                )
                Divider().padding(.leading, 16)
                reference("Reference: Mond")
                Divider().padding(.leading, 16)
                reference("Reference: 3105/erosion")
            }
            .padding(.vertical, 4)
            .wsCard(cornerRadius: 18)
        }
    }

    private var attributions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Upstream & exploit attributions")
            VStack(spacing: 0) {
                let rows: [(String, String, String)] = [
                    ("adnan.120hz/gievano", "WorkPlot developer", "https://github.com/adnan120hz/WorkSlop"),
                    ("GoldenNugget Developer", "Liquid Glass tweaks reference", "https://github.com/GoldenNugget-Team/GoldenNugget-mobile"),
                    ("forcequitOS", "bad_query", "https://github.com/forcequitOS"),
                    ("0xjohnnydev", "FilzaSlop / class-13 research", "https://github.com/0xjohnnydev"),
                    ("Mak5er", "AirCard-iOS — on-device AirLift", "https://github.com/Mak5er/AirCard-iOS"),
                    ("leminlimez", "Nugget & GestaltEdit", "https://github.com/leminlimez"),
                    ("rooootdev", "neospring (respring)", "https://github.com/rooootdev"),
                ]
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if row.0 == "rooootdev" {
                        credit(row.0, row.1, row.2, easterEgg: {
                            RespringHelper.shared.trigger()
                        })
                    } else {
                        credit(row.0, row.1, row.2)
                    }
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .wsCard(cornerRadius: 18)
        }
    }

    /// A linked credit row. `easterEgg`, when set, fires on a long press
    /// without blocking the row's normal tap-to-open-link behavior.
    private func credit(_ name: String, _ role: String, _ url: String, easterEgg: (() -> Void)? = nil) -> some View {
        let row = Link(destination: URL(string: url)!) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(role).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.wsBlue)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        return Group {
            if let easterEgg {
                row.simultaneousGesture(
                    LongPressGesture(minimumDuration: 10).onEnded { _ in easterEgg() }
                )
            } else {
                row
            }
        }
    }

    /// A credit row with several link chips under it, for entries that
    /// point at more than one repository.
    private func creditDual(name: String, role: String, links: [(label: String, url: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(role).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(links, id: \.url) { link in
                    Link(destination: URL(string: link.url)!) {
                        Label(link.label, systemImage: "link")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.wsBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Theme.wsBlue.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Theme.wsBlue.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    /// A plain text reference row with no link.
    private func reference(_ text: String) -> some View {
        HStack {
            Image(systemName: "bookmark")
                .font(.caption)
                .foregroundStyle(Theme.wsBlue)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - Thanks

    private var thanks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Big thanks to")
            VStack(alignment: .leading, spacing: 0) {
                Text("Everyone in the WorkSlop community who tested and reported issues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .wsCard(cornerRadius: 18)
        }
    }
}
