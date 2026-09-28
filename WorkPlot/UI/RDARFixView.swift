import SwiftUI

struct RDARFixView: View {
    @State private var resolutionText = ""
    @State private var status: String?

    // NOTE: version gating uses `WorkSlopSupport` (Models/WorkSlopSupport.swift).

    /// Version gate for the canvas fix, from `WorkSlopSupport.currentVersion`.
    private enum CanvasGate {
        /// iOS 27.0 dev beta 1–4 / public beta 1–2 — full function.
        case full
        /// iOS 26.6 / 26.6.2 — works, but experimental: show the banner.
        case experimental
        /// Anything else — the fix is not offered.
        case unsupported
    }

    private var gate: CanvasGate {
        let v = WorkSlopSupport.currentVersion
        if v.majorVersion == 27 && v.minorVersion == 0 { return .full }
        if v.majorVersion == 26 && v.minorVersion == 6 { return .experimental }
        return .unsupported
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Canvas RDARFix")

                switch gate {
                case .unsupported:
                    Text("The canvas fix is not supported on this iOS version (\(WorkSlopSupport.deviceLabel())).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .full, .experimental:
                    VStack(spacing: 14) {
                        if gate == .experimental {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.caution)
                                Text("EXPERIMENTAL on iOS 26.6 — the canvas fix may behave unexpectedly here. A backup of the stock plist is taken before any write.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.caution)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.caution.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        TextField("Resolution (e.g. 1179x2556)", text: $resolutionText)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        ActionButton(title: "Apply Canvas", systemImage: "wand.and.stars") { apply() }
                        if let status {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(status.hasPrefix("Failed") ? Theme.caution : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(18)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                SectionHeader("Info")
                Text("Rewrites the canvas route (MobileGestalt MainScreenCanvasSizes plus the IOMobileGraphicsFamily plist) so the screen resolution changes without a reboot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(Theme.pagePadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("RDARFix")
        .navigationBarTitleDisplayMode(.inline)
    }

    func apply() {
        do {
            let result = try RDARFix.apply(resolution: resolutionText)
            switch result {
            case .applied:
                status = "Canvas applied successfully"
            case .alreadyFixed:
                status = "Canvas already matches \(resolutionText.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }
}
