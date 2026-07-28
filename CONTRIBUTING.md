# Contributing to MicAI

Thanks for your interest. MicAI is an early personal prototype; contributions are welcome but expect a small surface area and shifting internals.

## Before you start

1. Read the [README](README.md) for requirements and quick start.
2. Skim [docs/BRIEF.md](docs/BRIEF.md) — it is the product/engineering source of truth.
3. Prefer small, focused changes with a clear verification step.

## Development setup

- macOS 14+
- Swift 6.x (`swift` on `PATH`; [swiftly](https://www.swift.org/install/) is fine)
- Apple Command Line Tools are enough — **do not use `xcodebuild` / Xcode project generation** for the supported build path

```bash
bash scripts/codex-build.sh
bash scripts/codex-test.sh
bash scripts/codex-lint.sh
```

## Secrets and auth

- Never commit tokens, keys, or `.env` files.
- AI Commands may read `~/.codex/auth.json` at runtime. Treat that file as **read-only** input — do not copy, log, or write credentials anywhere in the repo.
- Optional fallback: `OPENAI_API_KEY` from the environment only (never written to disk by MicAI).

## Pull requests

- Keep diffs scoped to the stated change.
- Include how you verified (which `scripts/codex-*.sh` commands, and any manual steps).
- Do not add internal agent/orchestration artifacts (for example under `.workflow/`) to user-facing docs.

## License

No open-source license is published yet. By contributing, you agree your work may be relicensed when a project license is chosen. If that is a blocker, open an issue first.
