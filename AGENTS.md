# MicAI

## Overview

Local-first AI dictation and AI-commands app for macOS: Parakeet TDT v2 on-device ASR + a selectable OpenAI LLM provider (API key by default; ChatGPT-subscription OAuth optional)

## Architecture

Swift package at repo root: `MicAICore` library (audio capture, Parakeet ASR via
FluidAudio, OpenAI API-key and ChatGPT-OAuth LLM clients, command engine) + `MicAI`
executable (MenuBarExtra UI, global hotkeys, text insertion). See `docs/BRIEF.md`
(source of truth), `docs/SPEC.md`, `docs/PRD.md`, `docs/PLAN.md`.

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
- `OPENAI_API_KEY` (default provider) is read from the process environment only and
  is never persisted. `~/.codex/auth.json` (optional ChatGPT-subscription provider)
  is read-only input; never copy or write tokens anywhere. Never edit .env
  directly; keep secrets out of committed files.
- Keep CLAUDE.md concise and project-specific.
