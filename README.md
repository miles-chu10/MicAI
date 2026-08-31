# MicAI

Local-first AI dictation and AI commands for macOS.

Hold a hotkey, speak, and polished text lands at your cursor in any app — or speak a command and an LLM transforms your selection in place. Speech recognition runs on-device; AI commands use your ChatGPT subscription (no metered API key required for the default path).

> **Status:** early prototype (v0.1.0). Built as a personal / research P0. Expect rough edges, incomplete manual verification, and breaking changes. Not a polished App Store product.

## Features

- **Menu bar app** — SwiftUI `MenuBarExtra`, no Dock icon
- **Dictation** — push-to-talk or toggle; audio → on-device Parakeet TDT v2 → light cleanup → insert at cursor
- **AI Commands** — spoken instruction + current selection → ChatGPT → replace/insert in place
- **Recording HUD** — floating state panel (recording / transcribing / inserting) with Esc cancel
- **Onboarding & Settings** — Microphone + Accessibility guidance, ASR model prep, hotkeys, provider status

## Requirements

| Requirement | Notes |
| --- | --- |
| macOS 14+ | Apple Silicon recommended; package targets macOS 14 |
| Swift toolchain | Swift 6.x via [swiftly](https://www.swift.org/install/) or Apple Command Line Tools — **Xcode.app is not required** |
| Microphone | Dictation and voice commands |
| Accessibility | Text insertion / selection capture via synthetic paste |
| ChatGPT / Codex auth | AI Commands read `~/.codex/auth.json` (from [Codex CLI](https://github.com/openai/codex)) as a **read-only** credential source; optional `OPENAI_API_KEY` env fallback |

Network is needed for Swift package resolution and the first-run Parakeet CoreML model download from Hugging Face (`FluidInference/parakeet-tdt-0.6b-v2-coreml` via [FluidAudio](https://github.com/FluidInference/FluidAudio)). Ordinary dictation audio stays on-device.

## Quick start

```bash
git clone https://github.com/miles-chu10/MicAI.git
cd MicAI

# Build + assemble dist/MicAI.app (release, ad-hoc codesign)
bash scripts/codex-build.sh

# Build and open the app
bash scripts/codex-run.sh

# Optional: install to ~/Applications/MicAI.app
bash scripts/codex-install.sh
```

### Tests and checks

```bash
bash scripts/codex-test.sh        # swift test
bash scripts/codex-lint.sh        # swift format lint
bash scripts/codex-typecheck.sh   # debug build
```

Do **not** use `xcodebuild`. Packaging is pure SwiftPM: `swift build` plus a script that writes `Info.plist`, embeds an icon, and ad-hoc codesigns `dist/MicAI.app`.

## Privacy & local-first

1. **Dictation is local by default.** Microphone audio and ordinary dictation transcripts are processed on-device with Parakeet; they are not uploaded for ASR.
2. **AI is deliberate.** Only AI Commands (and optional explicitly enabled post-processing) send text to an LLM.
3. **Credentials stay put.** MicAI reads Codex auth from `~/.codex/auth.json` and never copies tokens into the repo, settings files, or logs. Do not commit `.env` files or secrets.

## Architecture (brief)

Swift package at the repo root:

| Target | Role |
| --- | --- |
| `MicAICore` | Audio capture, Parakeet ASR (FluidAudio), ChatGPT OAuth LLM client, command engine, insertion helpers |
| `MicAI` | Menu bar UI, global hotkeys, HUD, onboarding, settings, text insertion |

```
Hotkey → capture (16 kHz mono) → Parakeet ASR → cleanup
  ├─ Dictation → paste at cursor
  └─ AI Command → LLM (Codex auth / optional API key) → replace or insert
```

## Project layout

```
Package.swift          SwiftPM manifest (macOS 14+, FluidAudio)
Sources/MicAICore/     Shared library
Sources/MicAI/         App executable (MenuBarExtra UI)
Tests/MicAICoreTests/  Unit tests
scripts/               Build / run / test / lint entry points
docs/                  Product & engineering docs (see docs/README.md)
```

## Documentation

| Doc | Purpose |
| --- | --- |
| [docs/README.md](docs/README.md) | Doc index |
| [docs/BRIEF.md](docs/BRIEF.md) | Product/engineering source of truth |
| [docs/PRD.md](docs/PRD.md) | Requirements & positioning |
| [docs/SPEC.md](docs/SPEC.md) | Architecture & integration contracts |
| [docs/PLAN.md](docs/PLAN.md) | Implementation milestones |
| [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) | Prototype acceptance ledger |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to build, test, and contribute |

## License

No open-source license has been published yet. Until one is added, the default copyright applies (all rights reserved). If you need a license for reuse, open an issue.

## Acknowledgments

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet CoreML ASR on Apple platforms
- NVIDIA Parakeet TDT v2 — on-device speech recognition model family
