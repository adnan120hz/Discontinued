<div align="center">

<img src="docs/assets/workslop-logo.png" alt="WorkSlop app icon" width="128" height="128">

# WorkSlop

**On-device iOS system modification tools — no PC required**

<p>
  <img src="https://img.shields.io/badge/status-beta%201-orange?style=flat-square" alt="Beta 1">
  <img src="https://img.shields.io/badge/platform-iOS%2026.2%2B-black?style=flat-square&logo=apple&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift-orange?style=flat-square&logo=swift&logoColor=white" alt="Language">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-6E56CF?style=flat-square" alt="GPLv3"></a>
</p>

<a href="https://github.com/adnan120hz/WorkSlop/releases/latest"><b>Download IPA (Beta 1)</b></a> ·
<a href="#-requirements">Requirements</a> ·
<a href="#-install">Install</a> ·
<a href="#-credits">Credits</a>

</div>

> [!WARNING]
> **WorkSlop modifies system state through sandbox escapes and backup restores. It can break system features and may require restoring your device.**
>
> **ALWAYS keep a full backup of your device before using WorkSlop. We are NOT responsible for any damage, data loss, bootloops, or bricked devices. Use entirely at your own risk.**

## What is WorkSlop?

WorkSlop is a free iOS customization app that lets you modify system settings, apply tweaks, and customize your iPhone/iPad without a PC or jailbreak. It uses real exploit techniques (bad_query sandbox escape, AirLift, backup restore) to write system preferences.

**This is Beta 1** — expect bugs. Not all features are fully tested. See [Beta 1 Known Issues](#-beta-1-known-issues) below.

## Features

- 📱 **Tweaks** — MobileGestalt editor (iOS 27.0 dev beta 1–4 / public beta 1–2 only)
- 🖼️ **PosterBoard** — Wallpaper tweaks (iOS 26.6–26.6.2, 27.0 db1–4/pb1–2)
- 💎 **Liquid Glass Tweak** — Apple's Liquid Glass UI effect (iOS 26.2–26.x only)
- 📡 **AirLift** — On-device file access via AirCard pairing
- 🔧 **RDARFix** — Custom canvas resolution fix (experimental on iOS 26.6.x)
- 🛡️ **Backup & Restore** — Automatic backup before each write

## ⚠️ Beta 1 Known Issues

- **DarkSword / Other Exploit menu does NOT work in Beta 1.** The DarkSword kernel exploit backend is not bundled. The menu is a feature catalog only — all toggles are disabled.
- **Tweaks are not fully tested.** The tweak catalog has not been validated on all supported iOS versions. Some tweaks may not apply correctly.
- **RDARFix on iOS 26.6.x is experimental.** The canvas plist may not be reachable via bad_query on 26.6.x.
- **No device testing by developers.** This app is built on CI (GitHub Actions) without physical device testing. A green build means it compiled, not that it works on your device.

## 📋 Requirements

- iPhone or iPad running:
  - **Tweaks:** iOS 27.0 developer beta 1–4 / public beta 1–2
  - **PosterBoard:** iOS 26.6 / 26.6.1 / 26.6.2, iOS 27.0 db1–4 / pb1–2
  - **Liquid Glass:** iOS 26.2 – 26.x (NOT iOS 27, NOT iOS 18)
  - **RDARFix:** iOS 26.6.x (experimental) or 27.0 db1–4/pb1–2
- Sideloading method (AltStore, SideStore, TrollStore, or developer signing)

## 📲 Install

1. Download `WorkSlop.ipa` from the [latest release](https://github.com/adnan120hz/WorkSlop/releases/latest)
2. Sideload using your preferred method (AltStore / SideStore / TrollStore)
3. **Back up your device first** (iCloud or iTunes/Finder backup)
4. Open WorkSlop and follow the on-screen guides

## 📝 Activity Log

### Beta 1 (2026-09-29)
- Initial public beta release
- iOS-gated Tweaks menu (27.0 db1–4/pb1–2 only)
- PosterBoard menu (26.6–26.6.2, 27.0 betas)
- Liquid Glass menu (26.2–26.x, blocked on 27)
- RDARFix experimental support on 26.6.x
- AirLift on-device file access
- English UI

## ⚖️ License

WorkSlop is licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE).

This is required because WorkSlop is derived from GPL-licensed code (WorkPlot, bad_query). You may use, modify, and redistribute this software under the terms of the GPL-3.0.

Third-party components and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 🙏 Credits

- **adnan.120hz** — WorkSlop owner & main developer
- **Adnan.120hz & Gievano** — WorkPlot developers ([adnan120hz/WorkSlop](https://github.com/adnan120hz/WorkSlop), [gievano/WorkPlot](https://github.com/gievano/WorkPlot))
- **forcequitOS** ([forcequitOS/bad_query](https://github.com/forcequitOS/bad_query)) — bad_query sandbox escape
- **Mak5er** ([Mak5er/AirCard-iOS](https://github.com/Mak5er/AirCard-iOS)) — AirCard on-device implementation
- **Johnny Franks** ([0xjohnnydev](https://github.com/0xjohnnydev)) — AirLift exploit, FilzaSlop technique
- **GoldenNugget** developer ([GoldenNugget-Team/GoldenNugget-mobile](https://github.com/GoldenNugget-Team/GoldenNugget-mobile)) — Liquid Glass tweak reference
- **mond** ([rooootdev/mond](https://github.com/rooootdev/mond)) — MobileGestalt research references

---

**Disclaimer:** WorkSlop is an independent project for iOS security research and education. Not affiliated with Apple Inc. All damage from using this software is your own responsibility. Keep a backup.
