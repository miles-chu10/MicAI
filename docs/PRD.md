# MicAI Product Requirements

## Product summary

MicAI is a local-first macOS menu bar app for fast voice input. Holding or toggling a global dictation hotkey records speech, transcribes it on-device with Parakeet TDT 0.6b v2, lightly cleans the transcript, and pastes it at the active cursor. A separate command hotkey combines a spoken instruction with the current selection and uses the user's ChatGPT subscription to replace or insert text.

The P0 product is a functional local prototype for macOS 14 or later. It is not a general voice assistant, a meeting recorder, or a cross-platform product.

## Product principles

1. Dictation is local by default. Raw microphone audio and ordinary dictation transcripts do not leave the Mac.
2. The active app stays the work surface. Users should not have to move text through a MicAI editor.
3. State is visible and cancellation is safe. Recording, transcription, insertion, and failures are explicit; Esc never inserts partial work.
4. AI is deliberate. Only AI Commands, and optional explicitly enabled post-processing, send text to an LLM.
5. Local prototype operation must not require Xcode, an API-key subscription, or a separate OAuth login.

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
- When the app needs sensitive permissions or a large model download, explain why, show progress, and let me recover.
- When I change my mind mid-recording, let Esc cancel without changing the target app or clipboard.

## Competitive positioning

This table describes current positioning, not benchmark superiority.

| Product | Current documented strengths | Tradeoff relative to MicAI P0 | MicAI position |
| --- | --- | --- | --- |
| [superwhisper](https://superwhisper.com/docs/get-started/sw-pro) | Voice dictation, local models, custom vocabulary, and AI-powered/custom modes across multiple Apple and desktop platforms | Mature paid product with broader modes and model choice | Narrow, inspectable prototype: fixed Parakeet v2 local ASR plus ChatGPT-subscription commands |
| [FluidVoice](https://github.com/altic-dev/FluidVoice) | Open-source macOS app positioned around fully local dictation and command/write modes | Closest open-source category peer; its feature set and architecture can change independently | Validate a minimal architecture built directly around FluidAudio and a replace-in-place command path |
| [Willow Voice](https://help.willowvoice.com/en/articles/10876920-dictating-with-willow-voice) | Cross-app hold-to-talk, hands-free mode, automatic formatting, and broad language support | Proprietary, broader cross-platform and personalization scope | English-first local ASR with transparent provider boundaries and no new account flow |
| [macOS Dictation](https://support.apple.com/guide/mac-help/mh40584/mac) | Built in, works wherever text can be entered, supports punctuation and formatting commands, and may process general dictation on-device depending on system settings | No MicAI-specific spoken LLM transformation workflow or provider/status UI | Add local Parakeet transcription and selected-text AI Commands while using familiar macOS interaction patterns |

## P0 user stories and acceptance criteria

### US-1: Complete first-run onboarding

As a new user, I want MicAI to explain and obtain what it needs before I try dictation.

Acceptance criteria:

- First launch presents a guided flow for Microphone, Accessibility, and the ASR model.
- The Microphone step triggers the system permission request and shows granted, denied, or not-determined state.
- The Accessibility step explains that global hotkeys and synthesized copy/paste require access, can trigger the system prompt, and provides a System Settings action.
- The model step downloads Parakeet TDT 0.6b v2 with visible progress and distinguishes downloading, compiling/loading, ready, and failed states.
- The user cannot finish onboarding with a hidden blocking state; skipped or denied steps remain visible in Settings.

### US-2: Dictate with push-to-talk

As a user, I want to hold Right Option, speak, and release to insert text.

Acceptance criteria:

- Right Option is the default configurable dictation hotkey.
- Key-down starts microphone capture and key-up stops it.
- Captured audio is 16 kHz mono Float32 before ASR.
- Parakeet TDT 0.6b v2 transcribes locally; only light deterministic cleanup runs by default.
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
- `make this uppercase` replaces the selected text with the returned transformation.
- The client uses the read-only Codex credential when available, re-reads it once after a 401, and never writes or logs token values.
- Empty, failed, cancelled, or incomplete LLM output does not replace the selection.

### US-5: Draft with an AI Command when nothing is selected

As a user, I want a spoken request to insert newly drafted content.

Acceptance criteria:

- An empty selection is represented explicitly rather than treated as a copy failure.
- A request such as `reply agreeing and propose Tuesday` inserts the LLM result at the cursor.
- The returned text is inserted only if the original target app remains eligible; otherwise MicAI reports that insertion was withheld.

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

- Settings exposes both hotkeys, dictation mode, LLM model string and provider status, ASR model status, and launch-at-login.
- Conflicting or unusable hotkey assignments are rejected with a specific message.
- Provider status distinguishes missing credential, ready-to-attempt, retrying after 401, and request failure; it does not expose credential values.
- Launch-at-login reflects the system service state rather than only the last toggle value.

### US-8: Operate as a menu bar utility

As a user, I want MicAI available without a Dock icon.

Acceptance criteria:

- Launching the app shows a persistent `MenuBarExtra`.
- The app bundle sets `LSUIElement` to true and does not show a normal Dock icon.
- The menu provides access to Settings, onboarding/status, and Quit.

## Out of scope for P0

- iOS app or keyboard extension
- Per-app modes or prompt profiles
- Custom vocabulary
- Streaming partial transcripts
- Transcription history or audio retention
- Multilingual ASR or a second speech engine
- A MicAI-owned OAuth browser flow
- Meeting capture, system-audio capture, diarization, or file transcription
- Autonomous computer control or arbitrary spoken actions
- Cloud sync, accounts, telemetry, payments, or App Store distribution
- General direct editing through the Accessibility text API; P0 uses copy/paste synthesis

## Success metrics

### Prototype gates

- 100% success for `bash scripts/codex-build.sh` on a clean supported clone with network access, producing a verifiable ad-hoc-signed `dist/MicAI.app`.
- All `bash scripts/codex-test.sh` MicAICore tests pass, including command routing, auth parsing, cancellation, SSE parsing, and guarded clipboard restoration.
- Five consecutive 10-second TextEdit dictations complete without crash or clipboard loss and meet the approximately two-second post-release target.
- The uppercase selected-text command succeeds in five consecutive controlled trials using ChatGPT-subscription OAuth.
- Esc produces zero insertions in five trials at recording, transcription, and LLM-wait stages.
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
| Focus changes while ASR/LLM work is pending | Text could enter the wrong app | Capture target identity, verify before insertion, withhold on mismatch |
| Clipboard content is lossy or overwritten concurrently | User data loss | Snapshot every pasteboard item/type, compare change count before restore, dependency-injected tests |
| FluidAudio API/model artifacts change | Build or runtime model preparation breaks | Exact package pin, adapter boundary, source-grounded API tests |
| ChatGPT backend rejects third-party clients or changes contract | AI Commands unavailable | Specific provider error, one credential reload on 401, environment-only API-key fallback after verified incompatibility |
| Selected text contains prompt-like content | LLM follows text rather than user instruction | Strong developer instruction, serialize instruction and selection as distinct data, output-only validation |
| Ad-hoc signing changes permission identity after rebuild | Permissions appear lost | Stable bundle identifier and bundle path; document local signing limitation |
| Local ASR latency misses target | Dictation feels slower than typing | Warm models after onboarding, measure ASR separately, avoid LLM post-processing by default |

## Open questions

1. Which deterministic cleanup rules are acceptable beyond trimming whitespace and normalizing obvious spacing without changing meaning?
2. Should a result withheld after a focus change be copied to the clipboard, displayed for manual recovery, or discarded?
3. What exact command-hotkey default avoids conflicts on the target keyboard layout?
4. Does the target macOS version require Input Monitoring in addition to Accessibility for the chosen global Right Option event-tap implementation?
5. What English evaluation phrases and microphones should define a repeatable quality baseline beyond the BRIEF's functional checks?
6. Should optional dictation post-processing ship disabled but visible, or remain absent from P0 UI?
