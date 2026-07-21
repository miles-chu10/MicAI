# MicAI — Product & Engineering Brief (optimized prompt)

One-liner: Local-first AI dictation and AI-commands app for macOS in the class of
superwhisper / FluidVoice / Willow Voice — hold a hotkey, speak, and polished text
lands at your cursor in any app; or speak a command and an LLM transforms your
selected text or drafts content in place.

This brief is the source of truth for generating `docs/PRD.md`, `docs/SPEC.md`, and
`docs/PLAN.md`, and for the prototype implementation that follows. Everything in
"Hard constraints" was verified on the target machine and is non-negotiable.

## Product scope

P0 (the fully functional prototype):
1. Menu bar app (SwiftUI `MenuBarExtra`, `LSUIElement` — no Dock icon).
2. Global hotkey, two modes: push-to-talk (hold) and toggle. Default hold Right-Option;
   configurable in Settings.
3. Dictation: audio → on-device ASR (Parakeet TDT v2) → light cleanup → text inserted
   at the cursor of the frontmost app.
4. AI Commands: second hotkey. Spoken instruction + current selection (if any) are sent
   to the LLM; the result replaces the selection or is inserted at the cursor.
   Examples: "make this more formal", "reply agreeing and propose Tuesday",
   "turn this into bullet points".
5. Recording HUD: small floating always-on-top panel showing state
   (idle / recording with level meter / transcribing / inserting) plus cancel (Esc).
6. Settings window: hotkeys, mode selection, LLM provider status, ASR model status
   (downloaded / downloading), launch-at-login toggle.
7. Onboarding: first-run flow that requests Microphone permission, walks through
   granting Accessibility, and triggers the ASR model download with progress.

P1 (design for, do not build): iOS app + keyboard extension sharing the core package;
per-app modes; custom vocabulary; streaming partial transcripts in the HUD;
transcription history; multilingual via a second engine.

## Model providers

ASR (local): NVIDIA Parakeet TDT 0.6b v2 via the FluidAudio Swift package
(https://github.com/FluidInference/FluidAudio, SPM). CoreML models auto-download at
first run from Hugging Face repo `FluidInference/parakeet-tdt-0.6b-v2-coreml`.
Audio: AVAudioEngine, 16 kHz mono Float32. IMPORTANT: verify FluidAudio's actual
public API from the resolved package sources under `.build/checkouts/` before writing
the spec's integration section — do not invent method names.

LLM (AI Commands + optional dictation post-processing): the user's ChatGPT
subscription via OAuth, not a metered API key.
- Reuse the Codex CLI credential at `~/.codex/auth.json` (fields include
  `tokens.access_token`, `tokens.account_id`, `tokens.refresh_token`). The Codex CLI
  keeps it refreshed; MicAI re-reads the file on each session and on a 401 re-reads
  once before surfacing an error. Do NOT implement an OAuth browser flow in the
  prototype; document it as P1.
- Endpoint: `https://chatgpt.com/backend-api/codex/responses` (Responses API shape,
  streaming SSE), headers `Authorization: Bearer <access_token>`,
  `chatgpt-account-id: <account_id>`, `OpenAI-Beta: responses=experimental`,
  `originator: codex_cli_rs`, plus a random `session_id` UUID. Verify the exact
  request shape against the installed codex-cli 0.144.6 (open source) rather than
  guessing; if the endpoint proves unusable from a third-party app, fall back to
  `OPENAI_API_KEY` from the environment (never written to disk) and record the
  finding in SPEC.md.
- Default model: the subscription's default GPT model; make it a settings string.

## Hard constraints (verified on this machine, 2026-07-21)

- macOS 27.0, Apple Silicon. NO Xcode.app and no `xcodebuild` — Command Line Tools
  only. The build MUST be pure SwiftPM: `swift build` + a `scripts/codex-build.sh`
  that assembles `MicAI.app` by hand (copy binary, write Info.plist with
  `LSUIElement=true`, `NSMicrophoneUsageDescription`, then ad-hoc `codesign --force
  --deep -s -`). No storyboards, no xibs, no asset catalogs requiring actool.
- Swift toolchain comes from swiftly (`~/.swiftly`); assume Swift 6.x with
  `swift build` available. Target macOS 14+ so FluidAudio and MenuBarExtra work.
- Text insertion: save clipboard → set transcript → synthesize Cmd+V via CGEvent →
  restore clipboard after a short delay. Reading the current selection for AI
  Commands: synthesize Cmd+C with clipboard save/restore. Both need Accessibility
  permission (`AXIsProcessTrusted`); prompt and deep-link to System Settings.
- Package layout: `MicAICore` library target (audio, ASR, LLM client, command engine —
  platform-agnostic where possible, for the future iOS app) and `MicAI` executable
  target (menu bar UI, hotkeys, insertion — AppKit-dependent). Tests on MicAICore.
- Secrets: never write tokens or keys to the repo or any dotfile; `auth.json` is
  read-only input. `.env` files are off-limits.
- Repo conventions already scaffolded: `src/`, `docs/`, `scripts/`, `AGENTS.md`,
  `CLAUDE.md`. Put the Swift package at repo root (`Package.swift`, `Sources/`,
  `Tests/`); `src/` may be removed. Keep `scripts/codex-build.sh`,
  `scripts/codex-run.sh`, `scripts/codex-test.sh` working as the only entry points.

## Acceptance criteria (prototype is "done" when)

1. `bash scripts/codex-build.sh` succeeds from a clean clone (network allowed for SPM
   and model download) and produces `dist/MicAI.app`.
2. Launching the app shows the menu bar icon; onboarding requests mic permission and
   explains Accessibility.
3. Holding the dictation hotkey records; releasing transcribes locally via Parakeet
   and inserts the text into TextEdit (or any focused text field) within ~2s for a
   10s utterance.
4. With text selected, the command hotkey + "make this uppercase" (spoken) replaces
   the selection with the LLM result using ChatGPT-subscription OAuth.
5. Esc cancels a recording without inserting anything.
6. `bash scripts/codex-test.sh` runs green unit tests for MicAICore (command routing,
   auth.json parsing, clipboard-restore logic with injected pasteboard).
7. No secrets on disk; `git status` clean of build artifacts (`dist/`, `.build/`
   ignored).

## Deliverables requested from GPT-5.6-Sol (this task)

1. `docs/PRD.md` — personas, jobs-to-be-done, competitive positioning table
   (superwhisper / FluidVoice / Willow / macOS built-in dictation), P0 user stories
   with acceptance criteria, out-of-scope list, success metrics, risks.
2. `docs/SPEC.md` — architecture diagram (mermaid), module breakdown with
   responsibilities and public interfaces, audio/ASR/LLM data flow, the verified
   FluidAudio API integration section, the verified ChatGPT-OAuth request contract,
   permission flows, error taxonomy, build/packaging design for the no-Xcode
   constraint, test strategy.
3. `docs/PLAN.md` — ordered implementation milestones (each independently runnable),
   with the file list and verification command per milestone.

Style: concrete over generic; every claim about an external API grounded in source
you actually read; flag uncertainties explicitly in a "Open questions" section
rather than hand-waving.
