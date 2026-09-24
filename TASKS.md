# MicAI — integrate/m7-9 run checklist

Branch `integrate/m7-9` (off `main`). Gate for every item: `codex-build`, `codex-test`, `codex-lint`, `codex-typecheck` green.

## Merge (done)
- [x] Commit stale WIP from main (Codex CLI provider, adaptive insertion) — 453f775
- [x] Merge jolly-babbage; CodexCLIClient as sole LLM client, blank model = subscription default — 3964d47
- [x] Merge proof-cross-platform-popup-milestone: visual system, window presenter, HUD; proof-draft flow not taken — 1eef7c1

## Milestone 7 — menu bar UX, HUD, onboarding, Settings, launch at login
- [ ] Four-way status (mic, Accessibility, speech model, LLM provider): reuse `AppReadiness`/`ReadinessBlocker`, fill test gaps; align PLAN.md file list
- [ ] `PermissionStatusView` rendering the projection; used in main window, onboarding, menu
- [ ] Hotkey capture: recorder control + pure capture/validation in core (tested); wider key-name table
- [ ] HUD: transient "Cancelled" state after Esc/cancel
- [ ] Apply NativeVisualStyle across Onboarding, main window, History, Ask answer
- [ ] Verify LSUIElement/no Dock icon, nonactivating HUD, launch-at-login status mapping

## Milestone 8 — robustness, privacy, performance
- [ ] `LocalMetrics` (MicAICore/Diagnostics): release-to-insertion and ASR timings, tested; surfaced in app
- [ ] Wire local-only OSLog telemetry (MicAITelemetry = PLAN's RedactedLogger) into operation lifecycle
- [ ] ASR warm-up after model load
- [ ] Failure-path review: missing/signed-out Codex CLI, nonzero exit, timeout, focus change, hotkey conflicts, cancel races
- [ ] Privacy audit: tracked files, bundle, logs, git status

## Milestone 9 — acceptance
- [ ] Update docs/ACCEPTANCE.md with automated evidence (clean-clone build, codesign, tests, ignore checks, secret scan)
- [ ] Manual rows (onboarding, TextEdit dictation timing, spoken command, Esc) — need the user at the Mac

## Found (for the user)
- Proof branch: AI-command "proof draft" approval flow, recoverable-insertion UI, OpenAI cloud transcription (no key storage) not taken. Install scripts (codex-install*.sh) and iOS sim scripts merged untouched, not reviewed (iOS scripts cannot run here: no Xcode).
- `.claude/settings.local.json` PostToolUse hook points at the dropped provenance script (dangling before this run too).
