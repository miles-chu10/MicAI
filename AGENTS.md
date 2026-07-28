# MicAI

## Overview

Local-first AI dictation and AI-commands app for macOS: Parakeet TDT v2 on-device ASR + ChatGPT-subscription OAuth as LLM provider

## Architecture

Swift package at repo root: `MicAICore` library (audio capture, Parakeet ASR via
FluidAudio, ChatGPT-OAuth LLM client, command engine) + `MicAI` executable
(MenuBarExtra UI, global hotkeys, text insertion). See `docs/BRIEF.md` (source of
truth), `docs/SPEC.md`, `docs/PRD.md`, `docs/PLAN.md`.

Tool routing: Codex-primary for implementation; Claude Code orchestrates, reviews,
and verifies builds.

## Build & Run

- Run: `bash scripts/codex-run.sh`
- Build: `bash scripts/codex-build.sh`

## Test

- Test: `bash scripts/codex-test.sh`
- Lint: `bash scripts/codex-lint.sh`
- Typecheck: `bash scripts/codex-typecheck.sh`

## Constraints

- No Xcode on this machine: pure SwiftPM only (`swift build`); `scripts/codex-build.sh`
  assembles `dist/MicAI.app` by hand and ad-hoc codesigns it. Never invoke `xcodebuild`.
- Swift 6.3.3 via swiftly (`~/.swiftly`); target macOS 14+.
- `~/.codex/auth.json` is read-only input for the LLM provider; never copy or write
  tokens anywhere. Never edit .env directly; keep secrets out of committed files.
- Keep CLAUDE.md concise and project-specific.

## Cursor Cloud specific instructions

Cursor Cloud agents run on **Linux (Ubuntu 24.04, x86_64)**. MicAI is a **macOS-only**
app, so the standard build/run/test path CANNOT complete in the cloud VM. Do not
treat build/run/test failures here as regressions — they are the expected platform
mismatch. Full dev work (`scripts/codex-build.sh`, `codex-run.sh`, `codex-test.sh`)
requires macOS 14+/Apple Silicon with the swiftly toolchain (see `docs/BRIEF.md`).

What breaks and why (Linux):
- `swift build`/`swift test` fail while compiling the `FluidAudio` dependency:
  `MachTaskSelfWrapper/MachTaskSelf.c` includes `mach/mach.h` (Darwin/Mach kernel
  header, macOS-only), and FluidAudio also ships an Apple `.xcframework` binary target.
- `MicAICore`/`MicAI` sources import `AVFoundation`, `AppKit`, `SwiftUI`, `CoreML`,
  `CoreGraphics`, `ServiceManagement` — none available on Linux Swift.
- The build/run scripts call macOS-only tooling (`plutil`, `codesign`, `iconutil`,
  `/usr/bin/open`, `swiftc -framework AppKit`).

What DOES work on Linux (only with a Swift toolchain installed, not present by default):
- `swift package resolve` (SwiftPM metadata resolves fine).
- Lint: `swift format lint --recursive --strict Package.swift Sources Tests`
  (i.e. `scripts/codex-lint.sh`) — parses syntax only, no Apple frameworks needed.

To lint in the cloud VM, install a Swift Linux toolchain on demand (this is a one-off,
NOT baked into the reliability-critical update script). Example:
`curl -fsSL https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz | tar xz -C /tmp`
then `sudo apt-get install -y libncurses6 libpython3-dev libedit2 libxml2 libcurl4 libz3-4`
and put `/tmp/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin` on `PATH`.
