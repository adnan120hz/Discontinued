# Changelog

All notable changes to WorkSlop. Newest first.

## Beta 1 — 2026-09-29

### Added
- 📱 **Tweaks menu** — MobileGestalt editor, iOS-gated to 27.0 developer beta 1–4 / public beta 1–2
- 🖼️ **PosterBoard menu** — Wallpaper tweaks for iOS 26.6 / 26.6.1 / 26.6.2 and 27.0 db1–4 / pb1–2
- 💎 **Liquid Glass Tweak menu** — Apple's Liquid Glass UI effect for iOS 26.2–26.x (blocked on iOS 27 and iOS 18)
- 🔧 **RDARFix** — Custom canvas resolution fix, experimental on iOS 26.6.x
- 📡 **AirLift** — On-device file access via AirCard pairing (ported from Mak5er/AirCard-iOS)

### Changed
- 🔒 Tweaks menu shows locked state (greyed out + lock icon) on unsupported iOS versions
- 📝 Settings header text changed to English: "iOS system modification tools • beta 1"
- 🖼️ Liquid Glass tweaks removed from Tweaks menu (now has its own dedicated tab)

### Known Issues
- ⚠️ DarkSword / Other Exploit menu does NOT work in Beta 1 (backend not bundled)
- ⚠️ Tweaks are not fully tested on all supported iOS versions
- ⚠️ RDARFix on iOS 26.6.x is experimental — canvas file may not be reachable
- ⚠️ No device testing by developers — green CI build means it compiled, not that it works

### Credits
- **adnan.120hz** — WorkSlop owner & main developer
- **Adnan.120hz & Gievano** — WorkPlot developers
- **forcequitOS** — bad_query sandbox escape
- **Mak5er** — AirCard on-device implementation
- **Johnny Franks (0xjohnnydev)** — AirLift exploit, FilzaSlop technique
- **GoldenNugget-Team** — Liquid Glass tweak reference
- **rooootdev/mond** — MobileGestalt research references

---

## 2026-08-26 (WorkPlot era)

### Changed
- 🛠️ Every screen is now English only, and status/error messages render properly instead of placeholder strings like "Common Failprefix".
- 📱 Device Spoof: tapping the card expands the wheel picker inline, matching the subtype tweak configuration style.
- 📱 Device Spoof now lives in the tweak catalog as a tile — tap to toggle, wheel picker inline, applied with the staged batch (full identity blast unchanged).
- 🧾 Credits trimmed: dropped the 3105 entry after its feature was removed; FilzaSlop is now credited as class-13 research only.

### Fixed
- 🖼️ PosterBoard: Apple device wallpaper packs (e.g. "iPhone 17 Pro") now apply their own art instead of falling back to the device's default set. The importer now reads each pack's real PosterBoard extension (container layout, e.g. `com.apple.MercuryPoster`) instead of forcing everything into Collections.

### Removed
- 🔥 File Patch Workspace, App Containers, per-app cache cleaner, `.3105` patch importer, and hex/SQLite viewers - the underlying file-access path never worked reliably on device (#72).

## 2026-08-25 (WorkPlot era)

### Changed
- 🎨 Accent color now drives the app tint across views; display grid gap fixed by merging tool tiles into tweak rows.
- 🖥️ Device Spoof picker restyled as an inline wheel, consistent with subtype tweaks.
- 📖 README restyled: centered header with logo and badges, simplified install steps via iLoader, compatibility table.

## 2026-08-24 (WorkPlot era)

### Fixed
- 🐛 UI freezes when applying RDAR / Custom Canvas / Disable Liquid Glass (heavy work moved off the main thread).
- 🔒 Missing sandbox lease caused EPERM failures on Dynamic Island and Liquid Glass writes.
- 🔄 Respring now shows the overlay immediately and arms the crash after apply completes.
