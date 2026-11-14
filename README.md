<div align="center">

# 📋 TapCopy

**Select. Click. Copied.**

A native macOS utility from **BLACK EYE** that turns any text selection into a one-click action — no shortcuts, no focus stealing.

[**English**](README.md) · [**Español**](README.es.md)

</div>

&nbsp;

TapCopy watches your selection gestures, reads the text through the Accessibility API, and floats a small *Chameleon Pill* next to your cursor. One click copies. The same pill can open links, reveal files, convert colors, do math, transform text, search the web, or pin snippets on screen.

## ✨ Why TapCopy?

Copying text you already selected should not require a keyboard. Today it means reaching for ⌘C, losing your place, or installing a browser extension that only works inside one app.

TapCopy works wherever macOS exposes a selection — Chrome, Brave, Arc, Safari, Cursor, VS Code, PDFs and native apps — while keeping your blue selection alive. It never touches the clipboard while reading, never opens a network request, and never asks for Screen Recording. Everything is computed locally in Swift and AppKit.

## 📲 Download

TapCopy is **notarized and distributed as a signed DMG**, but release binaries are not published on GitHub yet. The repository ships everything needed to produce the same build locally.

**Requirements**

- macOS 14 Sonoma or later (Apple Silicon).
- Xcode 15+ / Swift 5.10+.
- Accessibility permission (requested on first launch).
- To sign and notarize: a `Developer ID Application` certificate for team `YH6W55MP95` and a `notarytool` keychain profile named `ordena-notary`.

**Build and install**

```bash
git clone https://github.com/gabrieldave/tapcopy-macos.git
cd tapcopy-macos

# Signed, installed in /Applications, no DMG:
./scripts/build_and_notarize.sh --dev

# Full release: DMG + notarization + double stapling (app and DMG):
./scripts/build_and_notarize.sh
```

The pipeline writes `VERSION`, `BUILD`, `SHA256` and the DMG path to `dist/release-info.txt`.

## 🚀 How it works

1. **Install and launch** TapCopy. The app lives in the menu bar; a first-run prompt appears if Accessibility access is still pending.
2. **Grant Accessibility** in System Settings → Privacy & Security → Accessibility. The menu bar icon turns from a warning triangle into the clipboard glyph.
3. **Select text anywhere** — drag over a word or paragraph, double-click a word, or shift-click to extend a selection. TapCopy ignores plain clicks and drags shorter than 3.5 pt.
4. **Click a segment** on the pill that appears next to your cursor:
   - **Copiar** copies the selection (⌘C through the source app, with the captured text as fallback).
   - Contextual segments appear only when they apply — **Abrir**, **Mostrar**, a color swatch, or `= result`.
   - **Plano**, **Aa**, the magnifier and the **pin** are available when Chameleon Mode is on.
5. **Keep working.** The pill auto-hides after 5 seconds, or immediately with `Esc`, right-click or scroll. A ✓ badge confirms the action.

Everything is local: no account, no telemetry, no uploads.

## 🔐 Privacy in v1.1.0

Your selected text is processed **100% locally** on your Mac and is never uploaded, stored or transmitted. The only network requests TapCopy makes are:

- **License activation / deactivation** — the key, a salted SHA-256 device hash and the Mac name.
- **Signed update check** — an anonymous GET to `tapcopy.iareal.net/api/updates/latest`; the DMG is accepted only if its SHA-256 matches the manifest *and* the manifest's Ed25519 signature verifies against the public key embedded in the app.

No telemetry, no analytics, no accounts, no Screen Recording permission.

## 📖 Guides

There is no external documentation site yet. These are the verified procedures behind the app and its build pipeline.

### First-run checklist

- Confirm the menu bar shows `TapCopy activo · Píldora Camaleón`.
- Press **Probar píldora ahora** in the menu to render the pill without selecting anything.
- Open **Acerca de TapCopy…** to check version, chip, signature status and Accessibility state, and use **Copiar diagnóstico** when reporting an issue.

### Menu bar reference

- **Left click** — opens the full menu.
- **Right click** — turns TapCopy on or off instantly.
- **Modo Camaleón (4 funciones)** — enables or disables the four smart segments.
- **Pausar en *App*** — skips TapCopy for the frontmost app; the choice persists.
- **Permiso de Accesibilidad** — opens the exact System Settings pane.
- **Ocultar icono del Dock** — switches between Dock and menu-bar-only.
- **Iniciar al encender mi Mac** — registers the login item via `SMAppService`.

### Troubleshooting

If the pill never appears after a rebuild, macOS may hold a stale Accessibility entry for the previous binary:

```bash
./scripts/build_and_notarize.sh --dev --reset-tcc
```

Then re-enable TapCopy in System Settings. Runtime events are written to `~/Library/Logs/TapCopy.log`, including every selection read, the detected drag distance, excluded apps, TCC changes and anti-overlap repositioning.

## 🔧 Features

### The Chameleon Pill

- A single compact capsule that grows only with the segments that make sense for the current selection
- Never becomes key or main window, so the source app keeps focus and your selection stays highlighted
- Draggable-aware hit testing: clicking the pill never triggers a new selection read

### Contextual actions

- **Open links** — full URLs and bare domains such as `findaro.iareal.net`, opened in your default browser
- **Reveal files** — absolute and `~/` paths that exist on disk open in Finder with the item selected
- **Color conversion** — `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()` and `rgba()` render a live swatch and copy the opposite notation
- **Inline math** — `145 * 1.16`, `×`, `÷`, `%`, parentheses, `$` and thousands separators, evaluated by a hand-written parser that rejects dates and phone numbers

### Text tools

- **Plano** — strips styles, non-breaking spaces, zero-width characters, soft hyphens, trailing whitespace and repeated blank lines
- **Aa** — `MAYÚSCULAS`, `minúsculas`, `Tipo Título`, `snake_case`, `camelCase` and a Markdown code block
- Live word and character count inside the `Aa` menu

### Search without losing focus

- Magnifier segment opens a Google search for the selection
- Selections that look like code also offer **Buscar código en GitHub** and **Buscar en StackOverflow**

### Pin shelf

- Pin up to four fragments as floating cards that survive Space switches
- Cards are draggable, show a live preview, and copy on demand — your main clipboard stays untouched until you ask
- The oldest card is retired automatically when the fifth is pinned

### Anti-overlap engine

- Six candidate positions around the cursor, clamped to the visible screen area
- Detects third-party floating bars (PopClip, Raycast, DeepL, Grammarly, LookUp) and in-page toolbars through `CGWindowList`, without Screen Recording permission
- Prefers the area below the cursor, leaving the upper band free for web popovers, and re-checks collisions 160 ms after appearing
- Reads DOM-level toolbars (Gemini, Notion, ChatGPT, Claude, Medium, Google Docs) through the Accessibility tree, so in-page popovers are avoided too

### System integration

- Menu bar first, optional Dock icon, launch at login
- Per-app pause list stored in `UserDefaults`
- Adaptive menu bar icon: warning triangle when Accessibility is missing, outlined glyph when off, filled glyph when active
- Bilingual About window (ES / EN) with version, chip, signature verification and diagnostics export
- Runtime signature verification against team `YH6W55MP95` and hardware detection through `sysctl`
- Developer ID signing, Hardened Runtime, notarization and double stapling (app + DMG)

## ❓ New to GitHub?

You do not need a GitHub account to read or build this project.

1. Open the [repository](https://github.com/gabrieldave/tapcopy-macos).
2. Use the green **Code** button → **Download ZIP**, then unzip it — or clone it with the command shown above.
3. Open Terminal in the unzipped folder and run `./scripts/build_and_notarize.sh --dev`.
4. Drag `TapCopy.app` from `/Applications` into **System Settings → Privacy & Security → Accessibility** and switch it on.

There are currently no assets under **Releases**, because the notarized DMG is built and verified locally for each version.

## 📙 Contributing

TapCopy is an internal BLACK EYE tool published as a public repository. External pull requests and issues are not being accepted at this time. If you work inside BLACK EYE, keep changes scoped, preserve the protected files (`main.swift`, `SignatureVerifier.swift`, `TapLog.swift`, `scripts/GenerateIcon.swift`) and bump `version.txt` for every release.

## ❗ About

TapCopy is designed and developed by **David DEL RIO COLIN** for BLACK EYE, written in pure Swift with AppKit and no third-party dependencies. The icon is generated procedurally by `scripts/GenerateIcon.swift`; the pill, shelf and collision engine are custom AppKit views with no external UI framework.

Internal identity, logo and icon are property of BLACK EYE. Please do not reuse the name, icon or visual identity in derivative builds.

## 📜 License

No license file is provided. TapCopy is proprietary internal software: the source is public for reference, but all rights are reserved and redistribution, modification or commercial use requires written permission from BLACK EYE.

© 2026 BLACK EYE — David DEL RIO COLIN.
