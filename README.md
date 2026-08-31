# MicAI

Local-first AI dictation and AI-commands app for macOS: configurable
transcription with Parakeet TDT v2 on-device ASR or the OpenAI Audio API, plus
an experimental personal ChatGPT/Codex command route.

## Project status

MicAI is a personal-use prototype whose source is intended for public,
open-source development. The repository does not yet contain an open-source
license, so a license must be chosen before describing redistributed copies as
open source.

- Ordinary dictation defaults to Parakeet on-device. Settings can select an
  OpenAI transcription model and an explicit Parakeet offline fallback.
- The intended hosted route is `gpt-transcribe` through
  `POST /v1/audio/transcriptions` for a completed bounded recording. This build
  has no API-key source, so selecting or saving OpenAI never contacts the
  network; the UI reports the route as unavailable or uses prepared Parakeet
  when fallback is enabled.
- Recordings are converted to 16 kHz mono Float32 with FluidAudio's
  `AVAudioConverter` path and stop automatically at two minutes.
- Failed insertion keeps the completed result in memory for retry or manual
  copy, and new recordings wait until that result is resolved. MicAI does not
  persist transcription history or audio.
- AI Command results use **proof before paste**: they remain a session-only draft
  showing source, proposed text, local/network/destination receipt, and captured
  target until the user explicitly approves insertion. A changed target preserves
  the draft instead of inserting elsewhere.
- AI Commands use a read-only local Codex sign-in. This private experimental
  route is not a supported public OpenAI API authentication method and should
  not be presented as a distributable integration.
- No credential is bundled, copied, displayed, or written by MicAI. OpenAI API
  key storage, billing verification, and the first live transcription remain
  separate approval-gated work.
- Local diagnostics contain stable event/error codes and durations only. They
  omit dictated text, selections, app identities, credentials, requests, and
  file paths.

## Build and run

```bash
bash scripts/codex-build.sh
bash scripts/codex-run.sh
```


## Common Commands

```bash
bash scripts/codex-run.sh
bash scripts/codex-build.sh
bash scripts/codex-test.sh
bash scripts/codex-lint.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build-ios-sim.sh
```

## iOS proof companion

The iOS target is a native SwiftUI companion for reviewing the same proof-carrying
draft model; it is not an iOS dictation or keyboard-extension implementation. Build
it without `xcodebuild`, then use an already booted Simulator:

```bash
bash scripts/codex-build-ios-sim.sh
bash scripts/codex-run-ios-sim.sh <simulator-udid> primary
```

Supported deterministic fixtures are `primary`, `approved`, `target-unavailable`,
`insertion-uncertain`, and `narrow`. They never request microphone permission or
invoke a provider.

## Project Structure

```
Package.swift  Swift package manifest
Sources/       MicAICore library and MicAI executable
Tests/         MicAICore unit tests and MicAI app-state regression tests
scripts/       Build, run, test, lint, and typecheck entry points
docs/          Product, engineering, and acceptance documentation
```

`Package.swift` defines both `MicAICoreTests` and `MicAIAppTests` targets.
`bash scripts/codex-test.sh` runs both through the package-wide Swift test command.

## Transcription settings

Settings separates ordinary dictation from AI Commands:

- **Parakeet — On-device** is the compatibility-safe default and requires the
  local model to be prepared.
- **OpenAI — Recommended** exposes an editable transcription model, defaulting
  to `gpt-transcribe`, plus an explicit Parakeet fallback toggle.
- AI Command speech always uses Parakeet locally. Its text transformation route
  remains the separately labeled experimental personal Codex integration.

Provider choice, model text, and fallback preference persist in `UserDefaults`.
They never contain credentials, and saving them has no network side effect.
