import SwiftUI

// MARK: - RDARFix custom canvas (SUPER EXPERIMENTAL - no working write method)
//
// Honest status of the custom-canvas feature, verified 2026-09-30 against
// the actual WorkSlop codebase (adnan120hz/WorkSlop @ 6c004bc):
//
// The canvas fix must write canvas_width/canvas_height into
// com.apple.iokit.IOMobileGraphicsFamily.plist
// (/var/mobile/Library/Preferences/..., see RDARFix.candidatePaths).
// On iOS 26.6/26.6.1/26.6.2 and 27.0 dev beta 1-4 / public beta 1-2,
// WorkSlop has exactly TWO verified outside-sandbox write primitives:
//
//   1. bad_query (BadQueryLeaseScope + InodeWriter.writeVerifiedInPlace)
//      - Excluded for this screen: the new method was specified WITHOUT
//        bad_query. The bad_query implementation still exists, untouched,
//        in WorkPlot/Core/RDARFix.swift, but this view does not call it.
//   2. AirLift (AirLiftFileWriter, on-device Rust core)
//      - Explicitly ruled out by the user for RDARFix custom canvas.
//
// Everything else in the app that looks like a third method is one of the
// two above under a different name:
//   - The Liquid Glass "partial-restore" / "bookrestore-style" flow
//     (WorkPlot/Features/Backup/LiquidGlassBackupFlow.swift) captures
//     pre-images and writes them back via BadQueryLeaseScope.withLease +
//     InodeWriter.writeVerifiedInPlace. There is NO mobilebackup2 or
//     sparse_restore implementation in this repo - so there is no
//     backup-restore domain mapping that could carry the canvas plist.
//   - WallpaperSymlink (WorkPlot/Features/Wallpaper/WallpaperSymlink.swift)
//     requires the bad_query escape first ("After the bad_query escape
//     (WPExploitManager grants filesystem access)").
//   - GestaltStore.applyPlistModifications likewise writes through the
//     bad_query lease (WorkPlot/Models/GestaltStore.swift).
//
// Real-world alternatives that do NOT cover these iOS versions:
//   - sparse_restore (CVE-2024-44252): patched in 17.7.1/18.1. Dead here.
//   - bookrestore (Books daemon escape, CVE-2025-46286): 18.2-26.1,
//     patched in 26.2b2. Dead on 26.6+.
//   - EnsWilde (itunesstored & bookassetd): its own README
//     (github.com/YangJiiii/EnsWilde) says "designed for iPhone and iPad
//     running the latest iOS Version 26.2b1", and it is sparserestore-based.
//     Does not cover 26.6/26.6.1/26.6.2 or 27.0.
//   - darksword kernel r/w: tool offsets exist only for 17.0-18.7.1 and
//     26.0-26.0.1 (see WorkSlopSupport). Not 26.6 / 27.0.
//   - kfd: 15.0-16.6.1 only. Not applicable.
//   - AFC: Media-scoped by design; cannot reach
//     /var/mobile/Library/Preferences.
//
// Conclusion: with bad_query and AirLift both excluded, there is NO real
// third file-write method in evidence for this path on
// iOS 26.6/26.6.1/26.6.2 or 27.0 db1-4/pb1-2. No exploit was fabricated.
// Apply stays disabled until a third method is genuinely verified
// on-device.

struct RDARFixView: View {
    @State private var resolutionText = ""

    // NOTE: version gating uses `WorkSlopSupport` (Models/WorkSlopSupport.swift).

    /// Version gate for the canvas fix, from `WorkSlopSupport.currentVersion`.
    /// Both offered states currently show the SUPER EXPERIMENTAL "no working
    /// write method" UI (see the comment block above) - the distinction only
    /// records where bad_query itself is in its support range.
    private enum CanvasGate {
        /// iOS 27.0 dev beta 1-4 / public beta 1-2.
        case full
        /// iOS 26.6 / 26.6.1 / 26.6.2 - bad_query reachability of the canvas
        /// plist here is additionally unverified on-device.
        case experimental
        /// Anything else - the fix is not offered.
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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("SUPER EXPERIMENTAL - no working write method on this iOS version.")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Text("The custom canvas fix must write into com.apple.iokit.IOMobileGraphicsFamily.plist under /var/mobile/Library/Preferences. WorkSlop's only verified write primitives on iOS 26.6-26.6.2 / 27.0 beta are bad_query and AirLift - this screen uses neither by design (bad_query is excluded from the new method; AirLift was ruled out by the user). The app's \"partial-restore\" flow is bad_query under the hood, and sparse_restore / bookrestore / EnsWilde / darksword / kfd do not cover these iOS versions. Apply stays disabled until a third method is genuinely verified on-device - nothing was fabricated here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("Resolution (e.g. 1179x2556)", text: $resolutionText)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .disabled(true)
                        ActionButton(title: "Apply Canvas", systemImage: "wand.and.stars", disabled: true) {}
                    }
                    .padding(18)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                SectionHeader("Info")
                Text("This screen would rewrite the canvas route (canvas_width / canvas_height in the IOMobileGraphicsFamily plist) so the screen resolution changes without a reboot. It is currently non-functional: the bad_query implementation remains in Core/RDARFix.swift but is not wired to this UI, AirLift is excluded by user order, and no other write primitive on iOS 26.6-26.6.2 / 27.0 beta can reach the canvas plist - see the comment block in RDARFixView.swift for the full investigation.")
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
}
