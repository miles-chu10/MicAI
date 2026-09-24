# MicAI — integrate/m7-9 run checklist

Branch `integrate/m7-9` (off `main`). Gate for every item: `codex-build`, `codex-test`, `codex-lint`, `codex-typecheck` green.

## Merge (done)
- [x] Commit stale WIP from main (Codex CLI provider, adaptive insertion) — 453f775
- [x] Merge jolly-babbage; CodexCLIClient as sole LLM client, blank model = subscription default — 3964d47
- [x] Merge proof-cross-platform-popup-milestone: visual system, window presenter, HUD; proof-draft flow not taken — 1eef7c1

## Milestone 7 — menu bar UX, HUD, onboarding, Settings, launch at login
- [x] Four-way status (mic, Accessibility, speech model, LLM provider): reuse `AppReadiness`/`ReadinessBlocker`, fill test gaps; align PLAN.md file list
- [x] `PermissionStatusView` rendering the projection; used in main window, onboarding, menu
- [x] Hotkey capture: recorder control + pure capture/validation in core (tested); wider key-name table
- [x] HUD: transient "Cancelled" state after Esc/cancel
- [x] Apply NativeVisualStyle across Onboarding, main window, History, Ask answer
- [x] Verify LSUIElement/no Dock icon (plist + clean clone), nonactivating HUD panel; launch-at-login login/logout check stays manual (runbook E)

## Milestone 8 — robustness, privacy, performance
- [x] `LocalMetrics` (MicAICore/Diagnostics): release-to-insertion and ASR timings, tested; surfaced in app
- [x] Wire local-only OSLog telemetry (MicAITelemetry = PLAN's RedactedLogger) into operation lifecycle
- [x] ASR warm-up after model load
- [x] Failure-path review (audit of 7 paths): fixed SIGPIPE crash on early codex exit, uncancellable dictation refinement (+ cancelled dictation saved to history), 'Cancelled' shown after paste, Right Option vs ⌥-chord collision, missing-CLI check moved before recording
- [x] Privacy audit: tracked files, bundle, logs, git status

## Milestone 9 — acceptance
- [x] Update docs/ACCEPTANCE.md with automated evidence (clean-clone build, codesign, tests, ignore checks, secret scan)
- [ ] Manual rows (onboarding, TextEdit dictation timing, spoken command, Esc) — need the user at the Mac

## Found (for the user)
- Proof branch: AI-command "proof draft" approval flow, recoverable-insertion UI, OpenAI cloud transcription (no key storage) not taken. Install scripts (codex-install*.sh) and iOS sim scripts merged untouched, not reviewed (iOS scripts cannot run here: no Xcode).
- `.claude/settings.local.json` PostToolUse hook points at the dropped provenance script (dangling before this run too).
- Ad-hoc signing changes the code identity every build, so macOS drops the Accessibility grant after each rebuild. A stable self-signed identity would fix it; needs your decision (creates a keychain identity).
- `ChatGPTResponsesClient`/`CodexAuthFileLoader`/`OpenAIAPIKeyClient`/OpenAI transcription remain as unused library code.
- Not fixed (setup-dependent): a Homebrew/npm `codex` (`#!/usr/bin/env node`) launched from a Finder-started app may not find `node` on the reduced PATH; shows a generic service error. This Mac uses the native `~/.local/bin/codex`.
- Codex auth-failure detection matches 3 stderr phrases that are not verified against real codex output.
