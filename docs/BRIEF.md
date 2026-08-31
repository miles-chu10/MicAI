# MicAI — Product & Engineering Brief (optimized prompt)

One-liner: Local-first AI dictation and AI-commands app for macOS in the class of
superwhisper / FluidVoice / Willow Voice — hold a hotkey, speak, and polished text
lands at your cursor in any app; or speak a command and review a target-locked,
proof-carrying proposal before transformed text can reach another app.

This brief is the source of truth for generating `docs/PRD.md`, `docs/SPEC.md`, and
`docs/PLAN.md`, and for the prototype implementation that follows. Everything in
"Hard constraints" was verified on the target machine and is non-negotiable.

## Product scope

P0 (the fully functional prototype):
1. Menu bar app (SwiftUI `MenuBarExtra`, `LSUIElement` — no Dock icon).
2. Global hotkey, two modes: push-to-talk (hold) and toggle. Default hold Right-Option;
   configurable in Settings.
3. Dictation: audio → the saved transcription route → light cleanup → text
   inserted at the cursor of the frontmost app. Parakeet TDT v2 is the
   on-device default and offline fallback. The intended hosted route is an
   editable OpenAI model, defaulting to `gpt-transcribe`, through the Audio
   Transcriptions API for the completed recording.
4. AI Commands: second hotkey. Spoken instruction + current selection (if any) are sent
   to the LLM; the result becomes a session-only proposal rather than an immediate
   replacement or paste. The user sees the source, proposed text, local/network/
   destination receipt, and captured target before explicitly approving insertion.
   A changed target withholds insertion and preserves the draft for retry, copy, or
   discard. Examples: "make this more formal", "reply agreeing and propose Tuesday",
   "turn this into bullet points".
5. Recording HUD: small floating always-on-top panel showing state
   (idle / recording with level meter / transcribing / inserting) plus cancel (Esc).
6. Settings window: hotkeys, mode selection, ordinary-dictation provider and
   model, explicit Parakeet fallback, LLM provider status, local ASR model
   status (downloaded / downloading), and launch-at-login toggle.
7. Onboarding: first-run flow that requests Microphone permission, walks through
   granting Accessibility, explains the selected/effective transcription route,
   and offers an explicit Parakeet model preparation action with progress.
8. Recoverable insertion: if completed text cannot be inserted, keep it in
   session memory with actions to retry the exact original field or copy it
   manually. Block a new recording until the user retries, copies, or dismisses
   that result.
9. iOS companion: a native SwiftUI proof-review surface reuses the shared draft
   model. It has deterministic simulator fixtures for primary, approved,
   target-unavailable, and accessibility-size states; it does not request the
   microphone or invoke an LLM/provider.

P1 (design for, do not build): keyboard extension and live iOS capture/insertion;
per-app modes; custom vocabulary; streaming partial transcripts in the HUD;
transcription history; multilingual via a second engine.

## Model providers

ASR (local): NVIDIA Parakeet TDT 0.6b v2 via the FluidAudio Swift package
(https://github.com/FluidInference/FluidAudio, SPM). CoreML models auto-download at
first run from Hugging Face repo `FluidInference/parakeet-tdt-0.6b-v2-coreml`.
Audio: capture with AVAudioEngine, cap each recording at 120 seconds, and use
FluidAudio's public `AudioConverter` (`AVAudioConverter` internally) to produce
16 kHz mono Float32. IMPORTANT: verify FluidAudio's actual public API from the
resolved package sources under `.build/checkouts/` before writing the spec's
integration section — do not invent method names.

ASR (hosted ordinary dictation): the OpenAI Audio Transcriptions API at
`POST https://api.openai.com/v1/audio/transcriptions`, using multipart `file`
and `model` fields. Default model: `gpt-transcribe`; keep the model editable in
Settings. MicAI uploads only a completed, 16 kHz mono PCM16 WAV bounded below
the API's 25 MB file limit. Do not use the Agents SDK for this path, and do not
use `gpt-live-transcribe` unless a separately scoped streaming/realtime feature
is approved. The current implementation intentionally supplies no production
API key, so selection/save performs no credential access or network request;
missing access either uses the explicitly enabled prepared Parakeet fallback or
blocks with a truthful status. API-key storage, billing, Keychain, and the first
live call are separate approval gates.

LLM (AI Commands): personal-use experimental access through the user's local
ChatGPT/Codex subscription sign-in, not a supported public OpenAI API
authentication method and not a distributable product integration.
- Reuse the Codex CLI credential at `~/.codex/auth.json` (fields include
  `tokens.access_token`, `tokens.account_id`, `tokens.refresh_token`). The Codex CLI
  keeps it refreshed; MicAI re-reads the file on each session and on a 401 re-reads
  once before surfacing an error. Do NOT implement an OAuth browser flow in the
  prototype; document it as P1.
- Endpoint: `https://chatgpt.com/backend-api/codex/responses` (Responses API shape,
  streaming SSE), headers `Authorization: Bearer <access_token>`,
  `chatgpt-account-id: <account_id>`, `originator: codex_cli_rs`, plus the
  source-parity request/session headers documented in SPEC.md. The Codex 0.144.6
  HTTP SSE path does not send `OpenAI-Beta: responses=experimental`. Verify the
  exact request shape against the pinned open-source Codex implementation rather
  than guessing. Do not activate the existing environment-only `OPENAI_API_KEY`
  adapter automatically; any future public-provider migration is a separate,
  explicit product decision.
- Default model: the subscription's default GPT model; make it a settings string.

## Hard constraints (verified on this machine, 2026-08-11)

- macOS 27.0, Apple Silicon. The project rule is **never invoke `xcodebuild`**, even
  when Simulator SDK tooling is present. The macOS build MUST remain pure SwiftPM:
  `swift build` + a `scripts/codex-build.sh`
  that assembles `MicAI.app` by hand (copy binary, write Info.plist with
  `LSUIElement=true`, `NSMicrophoneUsageDescription`, then ad-hoc `codesign --force
  --deep -s -`). The iOS simulator fixture is compiled with `swiftc` and bundled by
  `scripts/codex-build-ios-sim.sh`; no storyboards, xibs, asset catalogs requiring
  actool, Xcode project, or `xcodebuild` are used.
- Swift toolchain comes from swiftly (`~/.swiftly`); assume Swift 6.x with
  `swift build` available. Target macOS 14+ so FluidAudio and MenuBarExtra work.
- Text insertion: save clipboard → set transcript → synthesize Cmd+V via CGEvent →
  restore clipboard after a short delay. Reading the current selection for AI
  Commands: synthesize Cmd+C with clipboard save/restore. Both need Accessibility
  permission (`AXIsProcessTrusted`); prompt and deep-link to System Settings.
- Capture the original focused AX element. Compare the selected-text range when
  the element supports it; do not reject otherwise valid focused controls solely
  because that optional attribute is unavailable. On insertion failure, preserve
  completed output in memory for exact-target retry or intentional clipboard copy.
- Package layout: `MicAICore` library target (audio, ASR, LLM client, command engine,
  and proof draft — platform-agnostic where possible), `MicAI` executable target
  (menu bar UI, hotkeys, insertion — AppKit-dependent), and `MicAIiOS` executable
  target (native proof-review companion). Tests cover the shared core.
- Secrets: never write tokens or keys to the repo or any dotfile; `auth.json` is
  read-only input for AI Commands only. Ordinary-dictation provider/model
  settings contain no key. `.env` files are off-limits, and a future OpenAI API
  key source requires an explicit Keychain/security decision.
- Diagnostics stay local and use redacted event/error codes plus durations only.
  Never log transcript/selection text, target app identity, credential/request
  content, or file paths.
- Repo conventions already scaffolded: `src/`, `docs/`, `scripts/`, `AGENTS.md`,
  `CLAUDE.md`. Put the Swift package at repo root (`Package.swift`, `Sources/`,
  `Tests/`); `src/` may be removed. Keep `scripts/codex-build.sh`,
  `scripts/codex-run.sh`, `scripts/codex-test.sh` working as the only entry points.

## Differentiating edge — proof-carrying dictation

Current category leaders already cover fast dictation, transformations, and privacy
controls: [Wispr Flow documents Command Mode and transforms](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode),
[superwhisper documents local models and modes](https://superwhisper.com/docs/modes/modes),
and [Willow documents privacy controls](https://help.willowvoice.com/en/articles/12854269-how-willow-protects-your-data-and-privacy).
Therefore, “AI dictation” or “local-first” alone is not a defensible claim.

MicAI's chosen edge is **safe, proof-carrying dictation**: an AI command creates a
session-only reviewable draft with the original text, proposal, explicit local versus
network receipt, and target-lock promise. The proposal cannot be pasted until the
user approves the originally captured destination. If that destination changes,
MicAI withholds insertion and retains a recoverable draft. This is a source-informed
product inference, not a claim that no competitor has any similar control.

## Acceptance criteria (prototype is "done" when)

1. `bash scripts/codex-build.sh` succeeds from a clean clone (network allowed for SPM
   and model download) and produces `dist/MicAI.app`.
2. Launching the app shows the menu bar icon; onboarding requests mic permission and
   explains Accessibility.
3. Holding the dictation hotkey records; releasing transcribes through the saved
   effective route and inserts the text into TextEdit (or any focused text
   field). Parakeet completes the local acceptance run within ~2s for a 10s
   utterance; the OpenAI route requires a separately approved credential,
   billing, and live-call run. Recording stops automatically at 120 seconds.
4. With text selected, the command hotkey + "make this uppercase" (spoken) creates
   a proof draft. Only explicit approval of the captured target may replace the
   selection; a changed target preserves the draft without insertion.
5. Esc cancels a recording without inserting anything.
   A non-cancel insertion failure preserves completed text for retry or copy.
6. `bash scripts/codex-test.sh` runs green unit tests for MicAICore (command routing,
   auth.json parsing, audio conversion/duration bounds, and clipboard/recovery
   behavior with injected boundaries).
7. No secrets on disk; `git status` clean of build artifacts (`dist/`, `.build/`
   ignored).
8. `bash scripts/codex-build-ios-sim.sh` builds the companion, and a booted iOS
   Simulator can launch the deterministic proof fixtures without mic, provider, or
   network access.

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
