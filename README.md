# MicAI

Local-first AI dictation and AI-commands app for macOS: Parakeet TDT v2 on-device ASR + ChatGPT-subscription OAuth as LLM provider

## Setup

```bash
bash scripts/codex-install.sh
```

The installer defaults to `/Applications/MicAI.app` so macOS privacy grants
attach to a stable bundle path. Use `MICAI_INSTALL_DIR=/path` only for isolated
packaging tests, not for Accessibility or microphone acceptance testing.

## Common Commands

```bash
bash scripts/codex-run.sh
bash scripts/codex-build.sh
bash scripts/codex-test.sh
bash scripts/codex-lint.sh
bash scripts/codex-typecheck.sh
```

## Project Structure

```
src/        Source code
config/     System configs
scripts/    Project helper scripts
docs/       Project documentation
```
