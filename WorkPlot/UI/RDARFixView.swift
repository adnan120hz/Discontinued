import SwiftUI

// MARK: - RDARFix custom canvas
//
// Two entries, split by iOS version:
//
// 1. "RDARFix (iOS 18 and below)" — uses the DarkSword / dirtyZero system.
//    DarkSword (kernel read/write, iOS 17.0-18.7.1) can reach the canvas
//    plist; dirtyZero (CVE-2025-24203, iOS 16.0-18.3.2) zeroes memory only
//    and cannot write files. The exploit backends are NOT bundled in
//    WorkSlop — this entry is gated to iOS 18 and below and explains why.
//
// 2. "RDARFix (iOS 26.6 and later)" — instructions only, no code runs.
//    Shows the manual workaround: subtype change + Settings Display Zoom.

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

    // MARK: - Entry 1: iOS 18 and below (DarkSword / dirtyZero system)

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

            Text("Uses the DarkSword / dirtyZero system. DarkSword provides kernel read/write on iOS 17.0-18.7.1 and can reach the canvas plist. dirtyZero (CVE-2025-24203, iOS 16.0-18.3.2) zeroes file memory only — it cannot write files, so it cannot apply this fix.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isLegacyIOS {
                Text("The DarkSword kernel exploit backend is not bundled in WorkSlop. This entry is shown for iOS 18 and below where the system can reach the canvas file. A full kernel exploit port is required to make Apply work.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                ActionButton(title: "Apply Canvas", systemImage: "wand.and.stars", disabled: true) {}
            } else {
                Text("Requires iOS 18 or below (DarkSword: iOS 17.0-18.7.1, dirtyZero: iOS 16.0-18.3.2). Not available on this iOS version (\(WorkSlopSupport.deviceLabel())).")
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

    // MARK: Helpers

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
