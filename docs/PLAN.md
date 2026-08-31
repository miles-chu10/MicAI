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

## Milestone 6 — LLM provider clients (OpenAI API key default, ChatGPT subscription opt-in) and AI Commands

Goal: transform a selection or draft text in place using the configured provider. The default provider posts to the standard OpenAI API; an opt-in provider uses the verified Codex 0.144.6 HTTP contract.

Work:

- Implement strict read-only decoding of `~/.codex/auth.json` for `tokens.access_token` and `tokens.account_id`.
- Implement the exact HTTP endpoint, verified headers, canonical request fields, and SSE parser from `SPEC.md`.
- Accumulate output deltas and require `response.completed`; discard failed, incomplete, empty, or cancelled output.
- On 401, reload credentials and retry once only.
- Build command payloads with separately JSON-encoded instruction and selected text.
- Route selection to replacement and no selection to insertion.
- Add an environment-only `OPENAI_API_KEY` client for the standard OpenAI API and make the provider a user-facing Settings choice (default: OpenAI API key).
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

Manual gate: with explicit approval, select `hello` in TextEdit, speak `make this uppercase`, verify `HELLO` replaces it with the configured provider (OpenAI API key by default), then verify an empty-selection draft. Repeat with the opt-in ChatGPT-subscription provider only with separate approval. Inspect logs and git status for absence of secrets.

Runnable result: both P0 AI Command provider paths work end to end, with the OpenAI API-key provider as the default.

## Milestone 7 — Complete menu bar UX, HUD, onboarding, Settings, and launch at login

Goal: replace diagnostic UI with the complete P0 utility experience.

Work:

- Finish `MenuBarExtra` content, Settings scene, and first-run onboarding.
- Implement a floating nonactivating HUD for recording level, transcribing, awaiting LLM, inserting, failure, and cancellation.
- Show separate microphone, Accessibility, ASR model, and LLM provider status.
- Add hotkey capture/validation, dictation-mode control, LLM model string, and launch-at-login.
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
- Measure capture-to-ASR and release-to-insertion timing locally.
- Warm the loaded ASR manager and remove avoidable main-thread work until the 10-second utterance target is met.
- Audit source, fixtures, logs, app bundle, and git status for credentials, audio, and build artifacts.
- Review the final diff for unrelated churn and missing tests.

Files:

- `Sources/MicAICore/Diagnostics/LocalMetrics.swift`
- `Sources/MicAI/Diagnostics/RedactedLogger.swift`
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
| 4. Selected-text uppercase command replaces via the configured provider | Select `hello`, invoke command hotkey, speak `make this uppercase`, verify `HELLO`; confirm the provider reports its credential path (OpenAI API key by default, ChatGPT subscription when selected) without exposing it | Five replacements, HTTP status/event completion diagnostics with all sensitive fields redacted |
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

## Open questions

1. Must the implementation pin FluidAudio with `exact: "0.15.5"` or use `from: "0.15.5"` while relying on `Package.resolved`? Exact pinning is safer for this prototype; the choice should be explicit in Milestone 1.
2. What clean-checkout mechanism should the scripts use instead of the current sibling `../.codex/scripts/local-dev-env.sh` dependency so acceptance criterion 1 is truly self-contained?
3. What deterministic audio fixture can be licensed and committed for optional local ASR integration testing without adding personal voice data?
4. Should the authenticated ChatGPT smoke test be a manual-only acceptance step or an opt-in script that requires explicit confirmation before making a request?
5. Which macOS 27 permissions reset procedure can be used safely for repeatable onboarding tests without disturbing unrelated apps?
6. Is launch-at-login logout/login verification required for prototype acceptance, or is `SMAppService.status` plus a relaunch check sufficient?
