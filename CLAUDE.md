# MicAI

Local-first AI dictation and AI-commands app for macOS: Parakeet TDT v2 on-device ASR + ChatGPT-subscription OAuth as LLM provider

Shared rules live in AGENTS.md — read it first (architecture, no-Xcode build
constraint, secrets rules). `docs/BRIEF.md` is the product/engineering source of truth.

## File Layout

```
Package.swift, Sources/, Tests/   Swift package (MicAICore + MicAI app)
scripts/                          Build/run/test entry points (pure SwiftPM)
docs/                             BRIEF, PRD, SPEC, PLAN
```

## Quick Commands

```bash
bash scripts/codex-build.sh   # swift build + assemble dist/MicAI.app + ad-hoc codesign
bash scripts/codex-run.sh
bash scripts/codex-test.sh
```
