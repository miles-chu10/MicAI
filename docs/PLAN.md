# MicAI Implementation Plan

## Planning rules

- Implement milestones in order. Each ends in a runnable package or app and has its own verification gate.
- Keep `MicAICore` testable with injected dependencies; isolate AppKit and global event plumbing in `MicAI`.
- Do not begin a later milestone while the current milestone's automated gate is red.
- Never use `xcodebuild`. All build, test, packaging, and signing operations use SwiftPM and the repo scripts.
- Never log, fixture, copy, or write real credentials. The production auth loader is read-only; tests use synthetic JSON.
- FluidAudio remains pinned to `0.15.5` until an explicit source-review upgrade.

## Milestone 1 — Replace the grounding manifest with a runnable Swift package and app bundle

Goal: establish the final two-target package and make every repo entry-point script work from the project root.

Work:

- Replace the throwaway `Package.swift` with products `MicAICore` and `MicAI`, macOS 14 minimum, FluidAudio `0.15.5`, and `MicAICoreTests`.
- Create the smallest compiling library and `@main` menu bar executable.
- Implement pure-SwiftPM debug/release build, test, lint/typecheck, run, and hand-built app packaging scripts.
- Build `Info.plist` in the script with a stable bundle identifier, `LSUIElement=true`, and `NSMicrophoneUsageDescription`.
- Ad-hoc sign and verify `dist/MicAI.app`.
- Remove the obsolete `src/` scaffold only after confirming it contains no needed work.
- Ensure `.build/`, `.swiftpm/`, `dist/`, and local research/cache directories are ignored or absent.

Files:

- `Package.swift`
- `Package.resolved`
- `Sources/MicAICore/MicAICore.swift`
- `Sources/MicAI/MicAIApp.swift`
- `Tests/MicAICoreTests/SmokeTests.swift`
- `scripts/codex-build.sh`
- `scripts/codex-run.sh`
- `scripts/codex-test.sh`
- `scripts/codex-lint.sh`
- `scripts/codex-typecheck.sh`
- `.gitignore`
- `src/` (remove)

Verification:

```bash
bash scripts/codex-typecheck.sh
bash scripts/codex-test.sh
bash scripts/codex-build.sh
test -x dist/MicAI.app/Contents/MacOS/MicAI
plutil -lint dist/MicAI.app/Contents/Info.plist
codesign --verify --deep --strict dist/MicAI.app
```

Runnable result: `bash scripts/codex-run.sh` launches a signed menu bar utility with Settings and Quit placeholders and no Dock icon.

## Milestone 2 — Core domain, settings, and operation state machine

Goal: define stable interfaces and prove safe single-operation/cancellation semantics before connecting hardware.

Work:

- Add domain types for modes, phases, target identity, transcript, insertion intent, and typed errors.
- Implement actor-isolated `OperationCoordinator` with one active operation, operation IDs, and cancellation.
- Add validated settings models for hotkeys, hold/toggle mode, and LLM model string.
- Keep settings serialization free of credentials and transient content.
- Add fakes and unit tests for legal transitions, concurrency rejection, cancellation, and stale result suppression.

Files:

- `Sources/MicAICore/Domain/MicAIMode.swift`
- `Sources/MicAICore/Domain/OperationPhase.swift`
- `Sources/MicAICore/Domain/MicAIError.swift`
- `Sources/MicAICore/Domain/TargetIdentity.swift`
- `Sources/MicAICore/Operation/OperationCoordinator.swift`
- `Sources/MicAICore/Settings/AppSettings.swift`
- `Sources/MicAI/Settings/SettingsStore.swift`
- `Tests/MicAICoreTests/OperationCoordinatorTests.swift`
- `Tests/MicAICoreTests/AppSettingsTests.swift`

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build.sh
```

Runnable result: the app opens Settings, persists non-secret settings, and exposes deterministic idle/operation state using fakes.

## Milestone 3 — FluidAudio v2 model preparation and local transcription

Goal: download/load the required local model and transcribe supplied 16 kHz Float32 samples using the verified API.

Work:

- Implement `SpeechRecognizing` and `FluidAudioRecognizer` using `AsrModels.downloadAndLoad(version: .v2, progressHandler:)`.
- Map `DownloadProgress` listing/downloading/compiling phases to app state on the main actor.
- Construct `AsrManager(config: .default, models: models)` and create a fresh `TdtDecoderState()` for every utterance.
- Call the verified `transcribe(_:decoderState:language:)` overload.
- Implement deterministic light cleanup and reject sub-0.3-second or empty results.
- Single-flight model preparation and warm the manager after onboarding.
- Compile the adapter in automated tests; use a fake recognizer for fast unit tests so the suite does not download models.

Files:

- `Sources/MicAICore/ASR/SpeechRecognizing.swift`
- `Sources/MicAICore/ASR/FluidAudioRecognizer.swift`
- `Sources/MicAICore/ASR/ModelPreparationState.swift`
- `Sources/MicAICore/ASR/TranscriptCleaner.swift`
- `Tests/MicAICoreTests/FluidAudioAdapterCompileTests.swift`
- `Tests/MicAICoreTests/TranscriptCleanerTests.swift`
- `Sources/MicAI/Views/ModelStatusView.swift`

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build.sh
bash scripts/codex-run.sh
```

Manual gate: trigger model preparation, observe real progress through ready, and transcribe a controlled sample locally without an LLM request.

Runnable result: the menu bar app can prepare Parakeet v2 and display a local transcription result in a temporary diagnostic view.

## Milestone 4 — Microphone capture and dictation orchestration

Goal: turn live microphone input into a cleaned transcript under hold and toggle state logic, without inserting yet.

Work:

- Implement `AVAudioEngine` capture, input level calculation, teardown, and conversion to 16 kHz mono Float32.
- Add microphone permission status/request through documented AVFoundation APIs.
- Connect hold/toggle transition logic to injected hotkey events before installing a global monitor.
- Connect capture to ASR through `OperationCoordinator`.
- Ensure Esc/cancel stops the engine and makes late ASR output inert.

Files:

- `Sources/MicAICore/Audio/AudioCapturing.swift`
- `Sources/MicAICore/Audio/AVAudioEngineCapture.swift`
- `Sources/MicAICore/Operation/DictationPipeline.swift`
- `Sources/MicAICore/Hotkeys/HotkeyStateMachine.swift`
- `Sources/MicAI/Permissions/MicrophonePermissionService.swift`
- `Tests/MicAICoreTests/HotkeyStateMachineTests.swift`
- `Tests/MicAICoreTests/DictationPipelineTests.swift`

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build.sh
bash scripts/codex-run.sh
```

Manual gate: grant microphone permission, record in both modes, observe live level and final transcript, and cancel five recordings without a late result.

Runnable result: hotkey-state controls live recording and local transcription; results are visible in MicAI but are not yet pasted.

## Milestone 5 — Accessibility, global hotkeys, selection capture, and safe insertion

Goal: reliably control recording globally and insert or replace text without losing clipboard contents.

Work:

- Implement Accessibility trust status and explicit onboarding prompt.
- Implement configurable global event monitoring for dictation, command, and Esc, including Right Option hold semantics and repeat suppression.
- Implement `SystemPasteboardAdapter` that snapshots all item type/data pairs and change count.
- Implement Cmd+C/Cmd+V synthesis with `CGEvent`.
- Implement selection capture, target process capture/revalidation, and delayed conditional clipboard restore.
- Add exhaustive tests using injected pasteboard and keyboard ports, including a concurrent external clipboard change.
- Wire dictation output to insertion only when the operation and target are still current.

Files:

- `Sources/MicAICore/Insertion/PasteboardAccessing.swift`
- `Sources/MicAICore/Insertion/TextInsertionCoordinator.swift`
- `Sources/MicAICore/Insertion/SelectionResult.swift`
- `Sources/MicAI/Hotkeys/GlobalHotkeyMonitor.swift`
- `Sources/MicAI/Insertion/SystemPasteboardAdapter.swift`
- `Sources/MicAI/Insertion/CGEventKeyboardSynthesizer.swift`
- `Sources/MicAI/Insertion/TargetApplicationTracker.swift`
- `Sources/MicAI/Permissions/AccessibilityPermissionService.swift`
- `Tests/MicAICoreTests/TextInsertionCoordinatorTests.swift`
- `Tests/MicAICoreTests/SelectionCaptureTests.swift`

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build.sh
bash scripts/codex-run.sh
```

Manual gate: in TextEdit, dictate through hold and toggle modes; verify rich/multi-item clipboard restoration, selection read, focus-change withholding, and Esc with no insertion.

Runnable result: local dictation works end to end in any compatible focused text field.

## Milestone 6 — ChatGPT-subscription SSE client and AI Commands

Goal: transform a selection or draft text in place using the verified Codex 0.144.6 HTTP contract.

Work:

- Implement strict read-only decoding of `~/.codex/auth.json` for `tokens.access_token` and `tokens.account_id`.
- Implement the exact HTTP endpoint, verified headers, canonical request fields, and SSE parser from `SPEC.md`.
- Accumulate output deltas and require `response.completed`; discard failed, incomplete, empty, or cancelled output.
- On 401, reload credentials and retry once only.
- Build command payloads with separately JSON-encoded instruction and selected text.
- Route selection to replacement and no selection to insertion.
- Keep the environment-only `OPENAI_API_KEY` adapter inactive; selecting a
  supported public API provider is a separate explicit migration, never an
  automatic response to private-route failure.
- Test entirely with fake credentials and an injected HTTP transport.

Files:

- `Sources/MicAICore/Auth/CodexAuthFileLoader.swift`
- `Sources/MicAICore/Auth/ChatGPTCredential.swift`
- `Sources/MicAICore/LLM/ChatGPTResponsesClient.swift`
- `Sources/MicAICore/LLM/ResponsesRequest.swift`
- `Sources/MicAICore/LLM/SSEParser.swift`
- `Sources/MicAICore/LLM/OpenAIAPIKeyClient.swift`
- `Sources/MicAICore/Command/CommandEngine.swift`
- `Sources/MicAICore/Operation/CommandPipeline.swift`
- `Tests/MicAICoreTests/CodexAuthFileLoaderTests.swift`
- `Tests/MicAICoreTests/ResponsesRequestTests.swift`
- `Tests/MicAICoreTests/SSEParserTests.swift`
- `Tests/MicAICoreTests/ChatGPTResponsesClientTests.swift`
- `Tests/MicAICoreTests/CommandEngineTests.swift`

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build.sh
bash scripts/codex-run.sh
```

Manual gate: with explicit approval to use the real subscription route, select `hello` in TextEdit, speak `make this uppercase`, verify `HELLO` replaces it, then verify an empty-selection draft. Inspect logs and git status for absence of secrets.

Runnable result: both P0 AI Command paths work end to end or the experimental
personal route is classified with a concrete backend incompatibility and remains
disabled pending an explicit supported-provider migration.

## Milestone 6A — Configurable ordinary-dictation providers

Goal: let ordinary dictation choose an inspectable local or hosted transcription
route without changing the local speech path used by AI Commands.

Work:

- Persist `DictationProvider`, an editable OpenAI transcription model defaulting
  to `gpt-transcribe`, and an explicit Parakeet fallback preference. Decode older
  settings as Parakeet for compatibility; store no credential.
- Snapshot provider/model/fallback at operation start and fence every provider
  status and result with the current operation ID.
- Encode completed 16 kHz mono samples as bounded PCM16 WAV and implement the
  exact multipart `POST /v1/audio/transcriptions` request behind injected API-key
  and HTTP transport ports. Do not use the Agents SDK or Realtime API.
- Route to Parakeet by default and on eligible failure only when fallback is
  enabled. Never fall back after cancellation.
- Keep the production API-key provider unavailable in this phase. Prove that
  selecting or saving OpenAI performs no key lookup or network request, and show
  API access, billing, and first-live-call as unverified in Settings.
- Add native provider/model/fallback controls plus selected/effective/status
  rows across Home, onboarding, Dictation, Settings, and the menu-bar menu.
- Preserve Parakeet as the unconditional local recognizer for AI Command speech.

Files:

- `Sources/MicAICore/ASR/SpeechTranscriptionRequest.swift`
- `Sources/MicAICore/ASR/DictationProviderStatus.swift`
- `Sources/MicAICore/ASR/OpenAITranscriptionClient.swift`
- `Sources/MicAICore/ASR/SpeechTranscriptionRouter.swift`
- `Sources/MicAICore/Auth/OpenAIAPIKeyProviding.swift`
- `Sources/MicAICore/Audio/PCM16WAVEncoder.swift`
- `Sources/MicAICore/Operation/DictationPipeline.swift`
- `Sources/MicAICore/Settings/AppSettings.swift`
- `Sources/MicAI/AppModel.swift`
- Existing native views and focused core/app test files

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-lint.sh
bash scripts/codex-build.sh
```

Manual gate: do not add or inspect a key, verify billing, use Keychain, record
audio, or make the first live transcription in this milestone. Those actions
require a separate approved security and privacy run.

Runnable result: Parakeet remains usable offline; OpenAI `gpt-transcribe` is a
fully modeled and fake-transport-tested choice whose unavailable live state is
truthful and non-networking.

## Milestone 7 — Complete menu bar UX, HUD, onboarding, Settings, and launch at login

Goal: replace diagnostic UI with the complete P0 utility experience.

Work:

- Finish `MenuBarExtra` content, Settings scene, and first-run onboarding.
- Implement a floating nonactivating HUD for recording level, transcribing, awaiting LLM, inserting, failure, and cancellation.
- Show separate microphone, Accessibility, ordinary-dictation route, local ASR
  model, and AI Command provider status.
- Add hotkey capture/validation, dictation-mode control, transcription
  provider/model/fallback, LLM model string, and launch-at-login.
- Implement `SMAppService.mainApp` registration/unregistration and status mapping.
- Ensure normal HUD/menu interaction does not steal focus from the insertion target.

Files:

- `Sources/MicAI/MicAIApp.swift`
- `Sources/MicAI/AppModel.swift`
- `Sources/MicAI/Views/MenuContentView.swift`
- `Sources/MicAI/Views/SettingsView.swift`
- `Sources/MicAI/Views/OnboardingView.swift`
- `Sources/MicAI/Views/PermissionStatusView.swift`
- `Sources/MicAI/HUD/RecordingHUDController.swift`
- `Sources/MicAI/HUD/RecordingHUDView.swift`
- `Sources/MicAI/LaunchAtLogin/LaunchAtLoginService.swift`
- `Tests/MicAICoreTests/StatusProjectionTests.swift`

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build.sh
plutil -p dist/MicAI.app/Contents/Info.plist
codesign --verify --deep --strict dist/MicAI.app
bash scripts/codex-run.sh
```

Manual gate: clear only MicAI's onboarding preference, relaunch, walk every step, confirm the menu icon/no Dock icon, exercise all HUD states, and verify launch-at-login status.

Runnable result: the full P0 app is usable without diagnostic UI or terminal interaction after launch.

## Milestone 8 — Robustness, privacy audit, and performance tuning

Goal: make the prototype dependable enough for the final acceptance run.

Work:

- Exercise permission denial/recovery, model offline/failure, missing/malformed auth, 401 retry, 403/429/5xx, broken SSE, focus changes, hotkey conflicts, and cancellation races.
- Convert captured audio through FluidAudio's AVAudioConverter-backed path, cap
  recordings at 120 seconds, and finish automatically when the cap is reached.
- Preserve completed output after insertion failure with explicit exact-target
  retry, clipboard copy, and dismissal actions.
- Treat the Codex subscription route as an experimental personal integration;
  never activate the API-key adapter automatically.
- Emit local unified-log events using stable redacted codes and durations only.
- Measure capture-to-ASR and release-to-insertion timing locally.
- Warm the loaded ASR manager and remove avoidable main-thread work until the 10-second utterance target is met.
- Audit source, fixtures, logs, app bundle, and git status for credentials, audio, and build artifacts.
- Review the final diff for unrelated churn and missing tests.

Files:

- `Sources/MicAICore/Audio/AVAudioEngineCapture.swift`
- `Sources/MicAI/Recovery/RecoverableInsertion.swift`
- `Sources/MicAI/Views/RecoveryResultView.swift`
- `Sources/MicAI/Diagnostics/MicAITelemetry.swift`
- Existing implementation files as targeted fixes require
- Existing `Tests/MicAICoreTests/*` as coverage requires

Verification:

```bash
bash scripts/codex-lint.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-test.sh
bash scripts/codex-build.sh
codesign --verify --deep --strict dist/MicAI.app
git status --short
```

Manual gate: five-trial dictation, command, and cancellation matrices pass; no sensitive value is displayed during the audit.

Runnable result: a release-built prototype ready for acceptance validation.

## Milestone 9 — Final acceptance, mapped 1:1 to the BRIEF

Goal: prove every BRIEF acceptance criterion without adding scope.

Files:

- `docs/ACCEPTANCE.md` for commands, observations, timings, and redacted evidence
- No planned production changes; any failure returns to the owning milestone and is fixed there

| BRIEF acceptance criterion | Final verification | Pass evidence |
| --- | --- | --- |
| 1. Clean-clone build produces `dist/MicAI.app` | In a clean checkout with network: `bash scripts/codex-build.sh`, `test -d dist/MicAI.app`, `codesign --verify --deep --strict dist/MicAI.app` | Command outputs, resolved dependency version, bundle tree, signature verification |
| 2. Launch shows menu icon and onboarding requests/explains permissions | `bash scripts/codex-run.sh`; complete first-run flow from not-determined microphone state and untrusted Accessibility state where practical | Menu/no-Dock observation plus each onboarding state recorded |
| 3. Hold dictation inserts a 10-second utterance in about two seconds | In TextEdit, hold Right Option, speak the fixed 10-second phrase, release, compare text, record release-to-insertion time; repeat five times | Five outputs and timings; median and worst case |
| 4. Selected-text uppercase command replaces via ChatGPT OAuth | Select `hello`, invoke command hotkey, speak `make this uppercase`, verify `HELLO`; confirm provider reports ChatGPT credential path without exposing it | Five replacements, HTTP status/event completion diagnostics with all sensitive fields redacted |
| 5. Esc cancels without insertion | Cancel once during recording, ASR, and LLM wait | Target text and clipboard unchanged after each case |
| 6. MicAICore unit tests are green for routing, auth parsing, and clipboard restore | `bash scripts/codex-test.sh` | Green test report naming the required suites |
| 7. No secrets or build artifacts are tracked | `git status --short` plus a secret-name-only scan of tracked files; verify `dist/` and `.build/` are ignored | No credential values; `git check-ignore dist .build` succeeds; only intended source/docs changes appear |

Final command gate:

```bash
bash scripts/codex-lint.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-test.sh
bash scripts/codex-build.sh
codesign --verify --deep --strict dist/MicAI.app
git check-ignore dist .build
git status --short
```

Done when every row in the table has recorded pass evidence and no unresolved P0 defect remains.

## Milestone 10 — Proof-carrying cross-platform command review

Status: implemented as a narrow vertical slice on 2026-08-11. This milestone does
not authorize live microphone, provider, TCC, target-app, keyboard-extension, or
installation testing.

Goal: make AI transformations reviewable and recoverable before cross-app paste, then
prove the same core receipt can render in macOS and iOS SwiftUI.

Implemented work:

- `MicAICore/Proof/ProofCarryingDraft.swift` provides immutable on-device,
  network, and target-lock receipt steps.
- `AppModel`, the command pipeline, and macOS proof views stage an AI command as a
  pending draft; approval is target-locked and failed reactivation preserves it.
- `MicAIiOS` reuses the shared receipt with deterministic primary, approved,
  target-unavailable, and narrow/accessibility fixtures.
- Manual iOS Simulator bundle/run scripts avoid `xcodebuild` and build only the
  fixture-backed shared core surface.

Files:

- `Sources/MicAICore/Proof/ProofCarryingDraft.swift`
- `Sources/MicAI/Recovery/PendingProofDraft.swift`
- `Sources/MicAI/Views/ProofDraftView.swift`
- `Sources/MicAIiOS/MicAIiOSApp.swift`
- `Sources/MicAIiOS/IOSUIEvidenceReporter.swift`
- `Tests/MicAICoreTests/ProofCarryingDraftTests.swift`
- `scripts/codex-build-ios-sim.sh`
- `scripts/codex-run-ios-sim.sh`

Verification:

```bash
bash scripts/codex-test.sh
bash scripts/codex-typecheck.sh
bash scripts/codex-build.sh
bash scripts/codex-build-ios-sim.sh
```

Evidence gate: build/install/launch each iOS fixture in an already booted Simulator;
capture primary, target-unavailable, approved, and accessibility-size screenshots plus
hierarchy evidence. Exercise the macOS review UI with Computer Use without accepting
TCC prompts or changing a target application. A real command, target reactivation,
or live provider call remains an explicit approval-gated acceptance step.

## Open questions

1. Must the implementation pin FluidAudio with `exact: "0.15.5"` or use `from: "0.15.5"` while relying on `Package.resolved`? Exact pinning is safer for this prototype; the choice should be explicit in Milestone 1.
2. What clean-checkout mechanism should the scripts use instead of the current sibling `../.codex/scripts/local-dev-env.sh` dependency so acceptance criterion 1 is truly self-contained?
3. What deterministic audio fixture can be licensed and committed for optional local ASR integration testing without adding personal voice data?
4. Should the authenticated ChatGPT smoke test be a manual-only acceptance step or an opt-in script that requires explicit confirmation before making a request?
5. Which macOS 27 permissions reset procedure can be used safely for repeatable onboarding tests without disturbing unrelated apps?
6. Is launch-at-login logout/login verification required for prototype acceptance, or is `SMAppService.status` plus a relaunch check sufficient?
