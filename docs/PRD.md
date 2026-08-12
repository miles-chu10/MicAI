# MicAI Product Requirements

## Product summary

MicAI is a local-first macOS menu bar app for fast voice input. Holding or
toggling a global dictation hotkey records speech, transcribes the completed
recording through a saved route, lightly cleans the transcript, and pastes it at
the active cursor. Parakeet TDT 0.6b v2 is the on-device default and offline
fallback; the intended hosted option is an editable OpenAI Audio API model
defaulting to `gpt-transcribe`. A separate command hotkey combines a locally
transcribed spoken instruction with the current selection and uses an
experimental personal ChatGPT/Codex route to create a reviewable proposal before
any replacement or insertion.

The P0 product is a functional personal-use prototype for macOS 14 or later whose source is intended for public development. The milestone also includes a fixture-backed iOS proof-review companion, not iOS dictation or a keyboard extension. It is not a supported public OpenAI integration, a general voice assistant, or a meeting recorder.

## Product principles

1. Dictation is local by default. Selecting OpenAI is deliberate and clearly
   distinguishes the chosen route, the effective route, and the optional
   Parakeet fallback before any audio could leave the Mac.
2. The active app stays the work surface. Users should not have to move text through a MicAI editor.
3. State is visible and cancellation is safe. Recording, transcription, insertion, and failures are explicit; Esc never inserts partial work.
4. Network use is deliberate. A hosted dictation sends only a completed bounded
   audio file after explicit provider configuration; AI Commands send only the
   instruction and selected text through their separate provider path.
5. Local prototype operation must not require Xcode, an API-key subscription,
   or a separate OAuth login. OpenAI dictation may remain unavailable while
   Parakeet works locally.
6. Completed text remains recoverable in session memory when safe insertion cannot finish.
7. A command transformation is proof-carrying: show source, proposal, processing
   receipt, and captured target before any cross-app insertion; approval is explicit.

## Personas

### Privacy-conscious Mac professional

Writes email, documents, and messages throughout the day and wants accurate dictation without routinely uploading audio. Comfortable granting narrowly explained macOS permissions.

### High-volume writer or developer

Moves between editors, terminals, browsers, and chat apps. Wants one consistent hotkey, low latency, and spoken transformations such as reformatting or drafting replies.

### User reducing keyboard load

Uses voice input to reduce repetitive typing or accommodate temporary or ongoing motor strain. Needs reliable hold and toggle modes, obvious state, and a cancel path.

### Prototype evaluator

Needs a reproducible SwiftPM build, inspectable local behavior, and clear provider status before deciding whether MicAI merits broader productization.

## Jobs to be done

- When my cursor is in any ordinary text field, let me hold one key, speak naturally, and receive usable text without leaving the app.
- When I need a longer passage, let me toggle recording so I do not have to hold a key.
- When text needs revision, let me select it, speak an instruction, and replace it in place.
- When no text is selected, let the same command workflow draft new text at the cursor.
- When the app needs sensitive permissions, hosted API access, or a large model
  download, explain why, show the exact state, and let me recover.
- When I change my mind mid-recording, let Esc cancel without changing the target app or clipboard.

## Competitive positioning

This table describes current positioning, not benchmark superiority.

| Product | Current documented strengths | Tradeoff relative to MicAI P0 | MicAI position |
| --- | --- | --- | --- |
| [Wispr Flow](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode) | Voice-driven command mode, transformations, multi-surface apps, and recovery guidance for insertion failures | Mature command/dictation product; its published workflow can evolve independently | Make the trust boundary inspectable at the decision point: source, proposal, receipt, target lock, and deliberate approval |
| [superwhisper](https://superwhisper.com/docs/modes/modes) | Voice dictation, local models, and configurable AI/custom modes across Apple and desktop platforms | Local processing and transformations are already category expectations | Do not compete on “local-first” alone; make every transformation's local/network/destination path legible before paste |
| [Willow Voice](https://help.willowvoice.com/en/articles/12854269-how-willow-protects-your-data-and-privacy) | Cross-app voice input and documented privacy/data controls | Proprietary, broader cross-platform and personalization scope | A recoverable session-only proof draft avoids silent transformation insertion while retaining a clear privacy receipt |
| [macOS Dictation](https://support.apple.com/guide/mac-help/mh40584/mac) | Built in, works wherever text can be entered, supports punctuation and formatting commands, and may process general dictation on-device depending on system settings | No MicAI-specific spoken LLM transformation workflow or provider/status UI | Add local Parakeet transcription and selected-text AI Commands while using familiar macOS interaction patterns |

## Proof-carrying command milestone

The competitive research above supports one narrow differentiator: **safe,
proof-carrying dictation**. A command result is not an instruction to paste. It is a
session-only `ProofCarryingDraft` containing the selected source (when present), the
proposed text, a per-step local/network/destination receipt, and a label for the
captured target. The user can approve, copy, or discard. Approval reactivates and
verifies the captured field; a mismatch changes the state to target unavailable and
retains the draft. The iOS companion provides the same review language with
deterministic fixtures, not microphone or provider behavior.

This is a positioning inference from public product documentation, not a claim of
absolute novelty or a benchmark against competitors.

## P0 user stories and acceptance criteria

### US-1: Complete first-run onboarding

As a new user, I want MicAI to explain and obtain what it needs before I try dictation.

Acceptance criteria:

- First launch presents a guided flow for Microphone, Accessibility, the
  transcription route, and the optional local ASR model.
- The Microphone step triggers the system permission request and shows granted, denied, or not-determined state.
- The Accessibility step explains that global hotkeys and synthesized copy/paste require access, can trigger the system prompt, and provides a System Settings action.
- The transcription step shows selected and effective routes without claiming
  OpenAI is configured. Preparing Parakeet is an explicit action with visible
  downloading, compiling/loading, ready, and failed states.
- The user cannot finish onboarding with a hidden blocking state; skipped or denied steps remain visible in Settings.

### US-2: Dictate with push-to-talk

As a user, I want to hold Right Option, speak, and release to insert text.

Acceptance criteria:

- Right Option is the default configurable dictation hotkey.
- Key-down starts microphone capture and key-up stops it.
- Captured audio is 16 kHz mono Float32 before ASR.
- Sample-rate conversion uses FluidAudio's AVAudioConverter-backed path rather than manual interpolation.
- Recording stops and continues to transcription automatically at 120 seconds.
- The operation snapshots provider, model, and fallback settings when recording
  begins. Later Settings changes cannot reroute that in-flight recording.
- Parakeet TDT 0.6b v2 transcribes locally by default. The OpenAI option encodes
  a completed 16 kHz mono PCM16 WAV and targets `POST /v1/audio/transcriptions`
  with the saved model; only light deterministic cleanup follows either route.
- OpenAI selection/save never contacts the network. With no configured API key,
  prepared Parakeet is used only when fallback is explicitly enabled; otherwise
  dictation stays blocked with an actionable status.
- The transcript is inserted into TextEdit or another focused text field.
- A 10-second utterance is inserted within approximately two seconds after release on the target machine.
- The pre-existing clipboard is restored unless another process changes it during the insertion transaction.

### US-3: Dictate in toggle mode

As a user, I want a hands-free recording mode for longer passages.

Acceptance criteria:

- Settings offers push-to-talk and toggle modes.
- In toggle mode, the first hotkey activation starts and the next activation stops.
- Toggle mode uses the same transcription, cleanup, insertion, HUD, and cancellation behavior as push-to-talk.
- Repeated or auto-repeat key events do not create overlapping recordings.

### US-4: Transform selected text with an AI Command

As a user, I want to select text, hold the command hotkey, say an instruction, and replace the selection.

Acceptance criteria:

- A separately configurable command hotkey captures the current selection and spoken instruction.
- The spoken instruction is transcribed locally.
- The instruction and selected text, but not raw audio, are sent to the configured LLM.
- The returned transformation first appears as a proof draft with source, proposal,
  local/network/destination receipt, and captured target label.
- `make this uppercase` replaces the selected text only after explicit approval of
  that captured target.
- If focus or the selected field changed, no text is inserted into either target;
  the draft remains actionable for exact-target retry, copy, or discard.
- The client uses the read-only Codex credential when available, re-reads it once after a 401, and never writes or logs token values.
- Empty, failed, cancelled, or incomplete LLM output does not replace the selection.

### US-5: Draft with an AI Command when nothing is selected

As a user, I want a spoken request to insert newly drafted content.

Acceptance criteria:

- An empty selection is represented explicitly rather than treated as a copy failure.
- A request such as `reply agreeing and propose Tuesday` inserts the LLM result at the cursor.
- The returned text is inserted only if the original target app remains eligible; otherwise MicAI reports that insertion was withheld.
- A completed result that cannot be inserted remains visible in session memory with actions to retry the exact captured field or intentionally replace the clipboard with the result.
- A new recording stays blocked until the user retries, copies, or dismisses the saved result, preventing an implicit overwrite.

### US-6: See state and cancel safely

As a user, I want a compact HUD and an immediate cancel action.

Acceptance criteria:

- A small floating always-on-top HUD shows idle, recording with an input level, transcribing, waiting for LLM when applicable, and inserting.
- Pressing Esc during recording or subsequent processing cancels the operation.
- Cancellation stops capture/work, dismisses transient UI, and inserts nothing.
- A stale async result from a cancelled operation cannot insert later.

### US-7: Configure and inspect MicAI

As a user, I want Settings to make the app understandable and adjustable.

Acceptance criteria:

- Settings exposes both hotkeys, dictation mode, ordinary-dictation provider,
  editable OpenAI transcription model, Parakeet fallback, separate AI Command
  model/provider status, local ASR status, and launch-at-login.
- Conflicting or unusable hotkey assignments are rejected with a specific message.
- Dictation status distinguishes selected and effective routes, missing API
  access, fallback readiness, active provider, fallback, completion, and
  failure. It does not expose credential values.
- Saving provider/model settings performs no API-key lookup or network request.
- Provider UI labels the local Codex sign-in route as a personal experimental preview rather than a supported public OpenAI API integration.
- Launch-at-login reflects the system service state rather than only the last toggle value.

### US-8: Operate as a menu bar utility

As a user, I want MicAI available without a Dock icon.

Acceptance criteria:

- Launching the app shows a persistent `MenuBarExtra`.
- The app bundle sets `LSUIElement` to true and does not show a normal Dock icon.
- The menu provides access to Settings, onboarding/status, and Quit.

## Out of scope for P0

- iOS microphone capture, cross-app insertion, or keyboard extension
- Per-app modes or prompt profiles
- Custom vocabulary
- Streaming partial transcripts
- Transcription history or audio retention
- Multilingual ASR or a second speech engine
- OpenAI API-key entry/storage, billing setup, or automatic model discovery
- Streaming/realtime transcription with `gpt-live-transcribe`
- A MicAI-owned OAuth browser flow
- Meeting capture, system-audio capture, diarization, or file transcription
- Autonomous computer control or arbitrary spoken actions
- Cloud sync, accounts, remote telemetry, payments, or App Store distribution
- General direct editing through the Accessibility text API; P0 uses copy/paste synthesis

## Success metrics

### Prototype gates

- 100% success for `bash scripts/codex-build.sh` on a clean supported clone with network access, producing a verifiable ad-hoc-signed `dist/MicAI.app`.
- All `bash scripts/codex-test.sh` MicAICore tests pass, including command routing, auth parsing, cancellation, SSE parsing, and guarded clipboard restoration.
- Five consecutive local Parakeet TextEdit dictations complete without crash or
  clipboard loss and meet the approximately two-second post-release target.
- The first hosted transcription remains a separate approved credential,
  billing, network, and privacy acceptance run.
- The uppercase selected-text command succeeds in five consecutive controlled trials using ChatGPT-subscription OAuth.
- Esc produces zero insertions in five trials at recording, transcription, and LLM-wait stages.
- The iOS proof companion builds, installs, launches, and renders deterministic
  primary, approved, target-unavailable, and accessibility-size fixtures in Simulator.
- No token, key, audio capture, model artifact, `dist/` content, or `.build/` content appears in tracked files.

### Diagnostic metrics collected locally

- Recording duration, ASR processing duration, insertion duration, and command round-trip duration.
- Count of cancelled, permission-blocked, auth-blocked, and insertion-withheld operations.
- No metric payload leaves the machine in P0.

## Risks and mitigations

| Risk | Impact | P0 mitigation |
| --- | --- | --- |
| Accessibility or microphone permission is denied | Hotkeys, capture, selection, or insertion fails | Explicit onboarding/status, preflight each operation, actionable recovery |
| Global hotkey conflicts or key events are not captured reliably | Core interaction becomes intermittent | Config validation, suppress auto-repeat, test both hold and toggle paths on the target OS |
| Focus changes while ASR/LLM work is pending | Text could enter the wrong app | Capture the focused AX element, verify supported selection range capabilities, withhold on mismatch, and retain completed output for recovery |
| Clipboard content is lossy or overwritten concurrently | User data loss | Snapshot every pasteboard item/type, compare change count before restore, dependency-injected tests |
| FluidAudio API/model artifacts change | Build or runtime model preparation breaks | Exact package pin, adapter boundary, source-grounded API tests |
| OpenAI transcription is selected without usable access | Dictation could fail or make a false privacy claim | No production key source in this phase; separate selected/effective route UI; explicit prepared-Parakeet fallback; fake-transport contract tests |
| A provider setting changes during transcription | An in-flight operation could switch destination or accept a stale result | Snapshot route per operation and fence every status/result with the operation ID |
| ChatGPT backend rejects third-party clients or changes contract | AI Commands unavailable | Label the route experimental, report a specific provider error, and reload the credential once on 401; never activate an API-key fallback automatically |
| Selected text contains prompt-like content | LLM follows text rather than user instruction | Strong developer instruction, serialize instruction and selection as distinct data, output-only validation |
| Ad-hoc signing changes permission identity after rebuild | Permissions appear lost | Stable bundle identifier and bundle path; document local signing limitation |
| Local ASR latency misses target | Dictation feels slower than typing | Warm models after onboarding, measure ASR separately, avoid LLM post-processing by default |

## Open questions

1. Which deterministic cleanup rules are acceptable beyond trimming whitespace and normalizing obvious spacing without changing meaning?
2. Which open-source license should govern redistribution of the public repository?
3. What exact command-hotkey default avoids conflicts on the target keyboard layout?
4. Does the target macOS version require Input Monitoring in addition to Accessibility for the chosen global Right Option event-tap implementation?
5. What English evaluation phrases and microphones should define a repeatable quality baseline beyond the BRIEF's functional checks?
6. Should optional dictation post-processing ship disabled but visible, or remain absent from P0 UI?
7. What approved Keychain and billing workflow should supply an OpenAI API key
   without exposing it to settings persistence, logs, or tests?
