import SwiftUI

// MARK: - RDARFix custom canvas
//
// Two entries, split by iOS version. Backend documented from the real
// implementation in WorkPlot/Core/RDARFix.swift — no fiction.

struct RDARFixView: View {

    // MARK: Version gates

    private var isLegacyIOS: Bool {
        let v = WorkSlopSupport.currentVersion
        return v.majorVersion <= 18
    }

    private var isModernIOS: Bool {
        let v = WorkSlopSupport.currentVersion
        if v.majorVersion == 26 && v.minorVersion == 6 { return true }
        if v.majorVersion == 27 { return true }
        return false
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Canvas RDARFix")

                legacySection
                modernSection
                backendSection

                SectionHeader("Info")
                Text("The canvas fix rewrites canvas_width / canvas_height in com.apple.iokit.IOMobileGraphicsFamily.plist so the screen resolution changes without a reboot.")
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

    // MARK: - Entry 1: iOS 18 and below

    private var legacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RDARFix — iOS 18 and below")
                    .font(.headline)
                Spacer()
                if isLegacyIOS {
                    Text("AVAILABLE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Supported builds:")
                .font(.footnote.weight(.semibold))
            buildCodeList

            if isLegacyIOS {
                Text("On iOS 17.0-18.7.1 the DarkSword kernel exploit can reach the canvas plist with kernel read/write. dirtyZero (iOS 16.0-18.3.2) zeroes file memory only and cannot write files, so it cannot apply this fix. The DarkSword kernel exploit backend is not bundled in WorkSlop.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                ActionButton(title: "Apply Canvas", systemImage: "wand.and.stars", disabled: true) {}
            } else {
                Text("Requires iOS 18 or below. Not available on this iOS version (\(WorkSlopSupport.deviceLabel())).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isLegacyIOS ? 1 : 0.6)
    }

    // MARK: - Entry 2: iOS 26.6 and later (instructions only)

    private var modernSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RDARFix — iOS 26.6 and later")
                    .font(.headline)
                Spacer()
                if isModernIOS {
                    Text("GUIDE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text("No code runs here. There is no working write method for the canvas plist on iOS 26.6 / 26.6.1 / 26.6.2 or iOS 27.0. Follow the manual workaround below instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isModernIOS {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Workaround steps")
                        .font(.subheadline.weight(.bold))

                    step(number: "1", title: "Change the subtype in Tweaks",
                         body: "Open the Tweaks menu and change the device subtype to match your series:")
                    subtypeTable

                    Text("This is an alternative method and does not always work. We will keep looking for the correct subtype for each iPhone model.")
                        .font(.footnote)
                        .foregroundStyle(.orange)

                    step(number: "2", title: "Open Settings",
                         body: "Open the Settings app on your iPhone.")
                    step(number: "3", title: "Scroll down",
                         body: "Scroll down in Settings.")
                    step(number: "4", title: "Find Appearance",
                         body: "On iOS 27, tap Appearance. On iOS 26, tap Display & Brightness.")
                    step(number: "5", title: "Display Zoom",
                         body: "Tap Display Zoom.")
                    step(number: "6", title: "Choose Larger Text",
                         body: "Select Larger Text, then tap Done. Your display will adjust.")
                }
                .padding(14)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("This guide is for iOS 26.6 / 26.6.1 / 26.6.2 and iOS 27.0. Not available on this iOS version (\(WorkSlopSupport.deviceLabel())).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isModernIOS ? 1 : 0.6)
    }

    // MARK: - Backend: how it works (real code)

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How the backend works")
                .font(.headline)

            Text("Real implementation from WorkPlot/Core/RDARFix.swift:")
                .font(.footnote.weight(.semibold))

            backendStep("1. Probe paths",
                       "Tries 4 candidate plist locations in order (RDARFix.candidatePaths): /var/Managed Preferences/mobile/, /var/mobile/Library/Preferences/, /var/preferences/ (two variants). The first path that exists wins.")
            backendStep("2. Acquire lease",
                       "Calls BadQueryLeaseScope.withLease(forPath:) — the bad_query sandbox escape grants a scoped file-access lease for the target path.")
            backendStep("3. Read plist",
                       "Reads com.apple.iokit.IOMobileGraphicsFamily.plist into memory as a dictionary.")
            backendStep("4. Patch canvas",
                       "RDARFix.applyCanvasSizesGestalt(to:) writes the new canvas_width and canvas_height values into the plist dictionary.")
            backendStep("5. Write back",
                       "InodeWriter.writeVerifiedInPlace writes the modified plist transactionally — it verifies the write landed before committing.")
            backendStep("6. Backup",
                       "A one-time copy of the stock plist is saved under \"RDAR Backups\" with metadata (path, date, byte count) so the original can always be restored.")

            Text("iOS support: bad_query covers iOS 26.6 / 26.6.1 / 26.6.2 and iOS 27.0 dev beta 1-4 / public beta 1-2. It does not cover iOS 17-18 — that is why the iOS 18-and-below entry above references the DarkSword system instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Build codes (real, from WorkSlopBuilds.database)

    private var buildCodeList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("iOS 17.x — 17.0 to 17.7 (DarkSword range, no build codes in database)")
                .font(.caption).foregroundStyle(.secondary)
            buildRow("18.0", "22A3374"); buildRow("18.1", "22B83")
            buildRow("18.2", "22C152"); buildRow("18.3", "22D75")
            buildRow("18.4", "22E240"); buildRow("18.5", "22F76")
            buildRow("18.6", "22G86"); buildRow("18.6.1", "22G90")
            buildRow("18.6.2", "22G100"); buildRow("18.7", "22H20")
            buildRow("18.7.1", "22H31"); buildRow("18.7.2", "22H124")
            Text("iOS 26.x / 27.x")
                .font(.caption.weight(.semibold)).padding(.top, 4)
            buildRow("26.0", "23A340"); buildRow("26.6", "23G71")
            buildRow("26.6.1", "23G82 / 23G83"); buildRow("26.6.2", "23G90")
            buildRow("26.7", "23H24")
            buildRow("27.0 db1", "24A5355Q"); buildRow("27.0 db2", "24A5370H")
            buildRow("27.0 db3 / pb1", "24A5380H"); buildRow("27.0 db4 / pb2", "24A5390F")
            buildRow("27.0 db5 / pb3", "24A5408D"); buildRow("27.0 db6", "24A5418B")
            buildRow("27.0 db7", "24A5424A"); buildRow("27.0 db8", "24A5430A")
            buildRow("27.0 RC", "24A435"); buildRow("27.0 stable", "24A437")
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func buildRow(_ version: String, _ build: String) -> some View {
        HStack {
            Text(version).font(.caption).frame(width: 110, alignment: .leading)
            Text(build).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func backendStep(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote.weight(.semibold))
            Text(body).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func step(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var subtypeTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            subtypeRow(phone: "iPhone 14 (base)", subtype: "iPhone 16 Pro")
            subtypeRow(phone: "iPhone 11", subtype: "iPhone 14 Pro Max")
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func subtypeRow(phone: String, subtype: String) -> some View {
        HStack {
            Text(phone).font(.footnote)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(subtype).font(.footnote.weight(.semibold)).foregroundStyle(.blue)
        }
    }
}
