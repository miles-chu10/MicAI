# MicAI prototype acceptance ledger

Date: 2026-08-11

This ledger maps one-to-one to the eight acceptance criteria in
`docs/BRIEF.md`. The current automated snapshot is branch
`codex/proof-cross-platform-popup-milestone`, based on `main` at `a7039f0`.
`PASS` means the full
criterion has direct current evidence. `MANUAL-ONLY` means implementation and
partial automation exist, but the required target-machine journey has not been
performed. `APPROVAL-BLOCKED` means the remaining check is automatable or
interactive but is behind an explicit user gate. No real credential,
permission, microphone, model-download, target-app, login-item, installation,
or network-dependent clean-clone action was used to prepare this ledger.

## BRIEF acceptance criteria

| # | Criterion | Status | Evidence and remaining boundary |
| --- | --- | --- | --- |
| 1 | A clean-clone `bash scripts/codex-build.sh` succeeds and produces `dist/MicAI.app`. | **APPROVAL-BLOCKED** | The current worktree release build passed on 2026-07-28 and produced a valid ad-hoc-signed arm64 app with a valid plist, nonempty `MicAI.icns`, macOS 14 minimum, and `LSUIElement=true`. A clean clone with cold dependency resolution was not attempted because that network/dependency-fetching check requires separate approval. |
| 2 | Launch shows the menu-bar icon; onboarding requests Microphone access and explains Accessibility. | **MANUAL-ONLY** | Source and bundle evidence cover `MenuBarExtra`, `LSUIElement`, the five-step onboarding UI, and the microphone usage string. The app was not launched, and the menu icon plus fresh-preference/TCC denial-and-recovery journey were not exercised. Follow Manual runbook A. |
| 3 | Holding the dictation hotkey records; release transcribes through the saved effective route and inserts into TextEdit. Parakeet meets the local latency target; OpenAI requires a separate approved live run. | **MANUAL-ONLY** | The operation snapshots provider/model/fallback, keeps AI Command speech local, and uses either Parakeet or a bounded PCM16 WAV Audio API request before common cleanup/insertion. Fake tests cover the exact multipart contract, 25 MB file bound, errors, cancellation, opt-in fallback, stale status isolation, and zero transport calls without an API key. No model was downloaded, audio recorded, TextEdit used, key accessed, or network call made. Follow runbook B for Parakeet and B-cloud only after its separate gates. |
| 4 | Selected text plus the spoken command “make this uppercase” replaces it using ChatGPT-subscription OAuth. | **APPROVAL-BLOCKED** | Request/auth/SSE behavior is fake-transport tested, including incremental byte streaming, cancellation, timeout, early EOF, completion, and one 401 credential reload. The source-parity HTTP SSE route omits the obsolete `OpenAI-Beta: responses=experimental` assumption. The personal Codex route remains experimental and unverified in the running app. No credential contents were accessed and no authenticated request was made. Follow Manual runbook C. |
| 5 | Escape cancels recording without inserting anything. | **MANUAL-ONLY** | Core cancellation and stale-result suppression tests pass, and the HUD/cross-phase Esc path is wired. A cancellation delivered from `operationStarted` is checked before audio capture begins, and a transport-level command cancellation clears the app operation slot so the next recording starts without a second cancel. Real global Esc, recording, ASR wait, LLM wait, HUD focus, and zero-insertion behavior were not exercised. Follow Manual runbook D. |
| 6 | `bash scripts/codex-test.sh` passes MicAICore tests covering command routing, auth parsing, and injected clipboard restoration. | **PASS** | The frozen MIL-45 run passed 110 MicAICore tests in 17 suites plus 8 AppModel regressions in 1 suite (118 tests in 18 suites aggregate). Coverage includes the established audio, auth, command, cancellation, recovery, and insertion suites plus provider settings migration, WAV encoding, exact OpenAI multipart transport, fallback routing, operation snapshots, and provider-status isolation. |
| 7 | No secrets are stored in the repo; `dist/` and `.build/` stay absent from `git status`. | **PASS** | No credential was read, printed, copied, or modified. A tracked-file name-only credential signature scan returned no matches; the only credential-related tracked files are the example environment file, auth model/loader source, and fake-fixture tests. `git status --short` showed no `.build/` or `dist/` artifacts, and `git check-ignore` confirmed both are ignored. The pre-existing untracked `.cursor/` metadata was preserved and not inspected. |
| 8 | The SwiftPM iOS companion builds and launches deterministic proof fixtures in a booted Simulator without microphone, provider, or network access. | **PASS** | `bash scripts/codex-build-ios-sim.sh` produced a signed arm64 iOS 17 Simulator app. Primary, approved, target-unavailable, insertion-uncertain, and narrow/accessibility fixtures launched in the booted iPhone 17e Simulator; screenshots and the opt-in UI hierarchy were captured under ignored `.build/` evidence. |

## P0 implementation readiness

| P0 feature | Implemented evidence | Remaining proof |
| --- | --- | --- |
| Menu bar app without a Dock icon | `MicAIApp` defines `MenuBarExtra`; the bundle has `LSUIElement=true`. | Launch and visually verify the menu-bar icon/no-Dock behavior. |
| Configurable hold/toggle hotkeys | Settings and hotkey state machines compile; hold, toggle, repeat, chord-release, and cancel unit tests pass. | Exercise real global event delivery and both activation modes. |
| Configurable dictation and guarded insertion | Backward-compatible provider/model/fallback settings, Parakeet routing, bounded WAV encoding, injected OpenAI multipart transport, route snapshots, provider-status fencing, common cleanup, guarded pasteboard restoration, and session-only recovery compile and have focused fake-boundary tests. The production API-key port is deliberately unavailable. | Prepare Parakeet and run microphone/TextEdit/latency, 120-second auto-stop, and retry/copy trials. Separately approve Keychain/API access, billing, and one live `gpt-transcribe` trial. |
| AI Commands | Selection routing, request encoding, auth parsing, SSE, retry, cancellation, recovery, and insertion intent have fake-boundary tests; the UI labels the route experimental/personal. | Run the approved live subscription trial and classify any backend/model incompatibility without automatic API fallback. |
| Recording HUD and Escape | HUD phases are wired; core cancellation and stale-result suppression pass; startup cancellation state is cleared. | Exercise the HUD and Escape in every reachable pre-paste phase. |
| Settings and launch at login | Settings exposes ordinary-dictation provider, editable model, explicit fallback, honest API/billing/live-call states, separate command status, readiness, and `SMAppService` integration. Saving provider settings has fake-backed proof of zero key/transport calls. | Change and verify Login Item state only with approval, including logout/login. |
| First-run onboarding | Welcome, Microphone, Accessibility, Transcription, and AI Command steps are present; selected/effective route and optional model preparation stay distinct. | Exercise fresh preferences, permission denial/recovery, provider states, and model progress with approval. |

## Manual verification runbook

Perform these steps only with the user's participation. Record observed
pass/fail results here afterward; do not record dictated/selected text,
credential values, request bodies, or token/path contents.

### A. Fresh onboarding and TCC recovery

1. Run `bash scripts/codex-build.sh`, quit every existing MicAI process, and
   launch `dist/MicAI.app`.
2. To exercise first-run presentation without touching unrelated preferences,
   first back up MicAI's own preferences with
   `defaults export com.mileschu.micai ~/Desktop/MicAI-pre-acceptance.plist`,
   then quit MicAI and run `defaults delete com.mileschu.micai`. Do not run a
   broad `tccutil reset`.
3. Relaunch and confirm onboarding visibly covers Welcome, Microphone,
   Accessibility, the transcription route, optional Parakeet model, and AI
   Commands. Confirm
   **Finish for Now** leaves unresolved blockers visible in Overview, Settings,
   and **Review Setup**.
4. On Microphone, click **Request Microphone Access** if status is
   undetermined. Deny once when practical, confirm MicAI remains blocked with an
   **Open Microphone Settings** recovery action, then enable only MicAI under
   System Settings → Privacy & Security → Microphone and return to MicAI.
5. On Accessibility, click **Request Accessibility Access**, confirm the UI
   does not immediately claim success, then enable only MicAI under System
   Settings → Privacy & Security → Accessibility. Return and click
   **Check Again**. If an existing grant prevents the blocked-state check,
   toggle only MicAI's entry off and on; do not reset other applications.
6. Quit and relaunch. Confirm both permission states refresh and remaining
   model/command blockers are still explicit.

### B. Parakeet preparation and TextEdit dictation

1. In Settings → Transcription, select **Parakeet — On-device** and save.
   In onboarding or Settings → Readiness, click **Prepare Local Model** or
   **Prepare**. Observe download/compile/load progress, wait for **Ready**, then
   quit and relaunch to confirm the cached model remains ready without another
   download.
2. Open TextEdit with a new plain-text document. Copy a recognizable clipboard
   sentinel before each trial so clipboard restoration can be checked afterward.
3. In Settings, select **Hold** and save. For five trials, focus TextEdit, hold
   the configured dictation hotkey, speak for about 10 seconds, release, and
   measure release-to-insertion time. Record each duration; the criterion is
   about two seconds. Confirm exactly one cleaned transcript is inserted and
   pasting afterward still yields the original clipboard sentinel.
4. Change Settings → Activation to **Toggle** and save. Press the dictation
   hotkey once, speak, and press it again. Confirm the same local pipeline
   inserts once and preserves the clipboard.
5. Start another trial, move focus to a different TextEdit field/document before
   insertion, and confirm MicAI withholds insertion from both the old and new
   target while preserving the completed result in **Activity**. Restore the
   original field and choose **Retry Original Field**; confirm one insertion.
   Repeat the withheld case and choose **Copy Result**; confirm it replaces the
   clipboard intentionally without synthesizing a paste.
   Before resolving another withheld result, press a recording hotkey and
   confirm MicAI keeps the result and asks you to retry, copy, or dismiss it.
6. Start another trial and press Escape before Cmd+V. Confirm zero insertion and
   clipboard restoration. Do not interpret Escape after text is already pasted
   as undo; that point is intentionally too late.
7. In a disposable TextEdit document, record until the two-minute cap. Confirm
   recording stops automatically, the full bounded capture is transcribed once,
   and releasing/pressing the hotkey afterward does not start a second finish.

### B-cloud. First real OpenAI dictation transcription

1. Stop unless Miles separately approves API-key handling, Keychain storage,
   billing verification, microphone use, the network request, and the target-app
   trial. The current build intentionally has no production API-key source.
2. After an approved key source exists, choose **OpenAI — Recommended**, retain
   model `gpt-transcribe`, decide explicitly whether Parakeet fallback is on,
   save, and confirm selected/effective/status rows agree. Saving alone must not
   contact OpenAI.
3. Record one short non-sensitive utterance. Confirm exactly one completed WAV
   request targets `POST /v1/audio/transcriptions`, the UI reports the active
   provider, and one result is inserted only into the captured target.
4. Record only HTTP classification, provider status transitions, insertion
   pass/fail, and whether fallback occurred. Do not record the key, audio,
   transcript, request body, or target-app identity.
5. With separate approval, exercise one controlled failure. Confirm fallback
   occurs only when enabled and Parakeet is prepared; cancellation must never
   trigger a fallback or late insertion.

### C. First real ChatGPT-subscription command

1. Obtain explicit approval immediately before this external call. Do not open
   or inspect the credential file.
2. In Settings, choose a command hotkey distinct from dictation, enter a
   supported subscription model, save, and confirm AI Commands reports ready to
   attempt.
3. In TextEdit type `hello`, select it, hold the command hotkey, say
   “make this uppercase,” and release. Confirm the result is `HELLO`, replacement
   occurs once, and no partial/failed output is inserted.
4. Put the cursor on an empty line with no selection, hold the command hotkey,
   speak a short drafting instruction, and release. Confirm the completed result
   is inserted rather than routed as a replacement.
5. Record only provider status, SSE result classification, and pass/fail. If the
   subscription route is rejected, stop; do not configure an API-key fallback,
   change provider metadata, or retry with credential experiments without a
   separate approval.

### D. HUD and Escape exercises

1. Focus TextEdit, close the primary MicAI window, and begin dictation. Confirm
   the floating HUD remains visible, does not activate MicAI, and never becomes
   the insertion target.
2. Exercise recording, transcribing, awaiting-LLM, inserting, cancelled, and the
   recoverable result presentation where safely practical. Confirm the level
   meter moves during recording and retry/copy actions stay disabled while a
   recovery attempt is active.
3. Press Escape during recording and verify zero insertion. Repeat while
   transcribing after release and while waiting for an LLM response; verify the
   operation returns to idle and late results remain inert.
4. Repeat the zero-insertion Escape checks five times for each reachable
   pre-paste phase. Confirm Escape after Cmd+V is classified as too late to undo
   while clipboard restoration still completes.

### E. Launch at login

1. In Settings → System, toggle **Launch MicAI at login** on and observe the
   displayed Login Item status from `SMAppService`.
2. If status says approval is required, enable only MicAI in System Settings →
   General → Login Items, return to MicAI, and confirm status refreshes.
3. Quit and relaunch MicAI, then log out and back in when practical. Confirm one
   MicAI instance starts and its menu/status surfaces remain usable.
4. Toggle launch at login off, confirm the authoritative status becomes
   disabled, and verify MicAI no longer starts at the next login.

### F. Redacted local telemetry

1. Run `log stream --level info --predicate 'subsystem == "com.mileschu.micai"'`
   in a terminal, then complete one short dictation, one cancellation, and one
   recoverable insertion failure.
2. Confirm stable operation phase/outcome, error-code, duration, limit, and
   recovery events appear as applicable.
3. Confirm the log contains no dictated or selected text, target app/bundle
   identity, credential/request content, raw error descriptions, or file paths.

## Final automated validation

The frozen MIL-45 packet passed the required automated gates on 2026-07-28 with
Swift 6.4:

- `bash scripts/codex-test.sh`: PASS — 110 MicAICore tests in 17 suites plus
  8 AppModel tests in 1 suite (118 tests in 18 suites aggregate).
- `bash scripts/codex-typecheck.sh`: PASS — debug build completed.
- `bash scripts/codex-lint.sh`: PASS — strict format lint exited zero.
- `bash scripts/codex-build.sh`: PASS — release compilation completed and
  assembled/ad-hoc-signed `dist/MicAI.app`.
- Shell syntax for all tracked scripts and `git diff --check`: PASS.

Provider coverage includes legacy Parakeet migration, editable OpenAI model
validation, exact PCM16 WAV and multipart request shape, response/error mapping,
opt-in fallback, cancellation, operation snapshots, stale status isolation, and
proof that selecting/saving OpenAI performs zero key and transport calls.

Post-build checks also passed:

- Shell syntax for every tracked `scripts/*.sh` entry point.
- Executable mode, nonempty icon, valid plist, `MicAI` executable/icon keys,
  `LSUIElement=true`, microphone usage text, and macOS 14 minimum.
- Thin arm64 Mach-O with `LC_BUILD_VERSION` minimum macOS 14.0.
- `codesign --verify --deep --strict`; signature reports `adhoc`.
- `.build/` and `dist/` ignore rules plus current git status review.
- Stable bundle identifier `com.mileschu.micai`, `LSUIElement=true`, and no
  credential/content fields in the new recovery or telemetry surfaces.

These automated passes do not verify installation, Finder/Applications launch,
foreground activation, one-window reuse, TCC, microphone/Accessibility,
Parakeet download, TextEdit/clipboard behavior, Keychain/API access, billing,
the first live OpenAI or ChatGPT request, launch at login, or manual visual QA.
Every such item remains unverified and behind its existing approval gate.

## Proof-carrying cross-platform milestone (2026-08-11)

This is a fixture-backed product/technical milestone, separate from the live P0
dictation and provider acceptance runs above.

| Gate | Evidence | Status |
| --- | --- | --- |
| Shared proof receipt | `ProofCarryingDraftTests` covers ordered on-device/network/target-lock steps, stable draft identity after a target failure, and terminal states | Automated gate |
| macOS review surface | Computer Use accessibility tree exposed the proof header, captured destination, source/proposal, all three privacy receipt rows, and Approve/Copy/Discard controls with identifiers and hints; screenshot captured during the same inspection | Observed; no target-app action taken |
| iOS primary | `dist-ios/MicAIiOS.app` installed/launched on booted `iPhone 17e` Simulator (`D875F1C2-2D90-4FD7-9163-477FA5D5D16D`); primary screenshot captured at `.build/ios-simulator-primary.png` | Observed |
| iOS target-unavailable | Deterministic fixture rendered “destination changed”, no insertion, and recoverable draft at `.build/ios-simulator-target-unavailable.png` | Observed |
| iOS approved | Deterministic fixture rendered companion-only approval at `.build/ios-simulator-approved.png`; it makes no network or cross-app request | Observed |
| iOS narrow/text fit | Accessibility-size fixture captured at `.build/ios-simulator-narrow-axl.png`; header/status reflow before long text | Observed |
| iOS hierarchy | Simulator-only, opt-in UIKit hosting hierarchy emitted to `.build/ios-simulator-ui-hierarchy.txt` | Observed fallback |

The iOS fixture evidence is a real Simulator build/install/launch/UI path, but it is
not microphone, provider, or keyboard-extension proof. The macOS target action was
not clicked: after the screen/tree/screenshot had been captured, repeated Computer
Use native-pipe failures and the safety coordination request to stop generating
`MicAIProofQA*.app` copies made further GUI action unsafe. The core target-failure
path remains covered by unit tests; live target reactivation, TCC, microphone, and
provider calls remain blocked behind their existing approval gates.

Post-review hardening preserves the exact source/proposal bytes, re-reads replacement
selection content before approval, exposes source/proposal accessibility values,
routes **Review Proof** to the proof surface, and distinguishes target changes from
other retryable approval failures. The 2026-08-11 post-fix gate passed focused proof
tests, strict lint, debug typecheck, all 124 tests in 19 suites, the signed macOS
release build, and the manual iOS Simulator build. Primary and approved Simulator
screenshots were refreshed from that post-fix bundle.

## Mode-specific popup integration (2026-08-11)

The separate popup lane was manually reconciled into the proof-safe `AppModel` rather
than copied over it. Dictation and AI Command retain their mode through recording,
transcribing, LLM wait, insertion/proof staging, failure, cancellation, and recovery;
terminal idle paths clear it without erasing the mode of a visible failure. The
nonactivating panel uses the pointer's screen only when first shown, so level updates
cannot make it jump between displays.

Deterministic `MICAI_UI_FIXTURE=hud-*` states exercise the signed bundle without
requesting Microphone or Accessibility access, invoking a provider, or inserting
text. Computer Use captured the command-recording accessibility summary and compact
waveform at `.build/hud-command-recording.png`, plus the non-cancellable target
failure and recovery guidance at `.build/hud-dictation-failed.png`. Both fixture
processes were terminated after capture. The focused AppModel/presentation suite
passed 13 tests before review. After review remediation, the full package passed
130 tests in 19 suites. Strict lint,
debug typecheck, signed macOS release build, iOS Simulator build/codesign, refreshed
primary Simulator screenshot, deterministic non-retry uncertainty evidence at
`.build/ios-simulator-insertion-uncertain.png`, and `git diff --check` also passed.

This fixture proof does not close the real global-hotkey, microphone, model/provider,
Escape zero-insertion, TextEdit target, TCC, login-item, or installed-app gates.

Fresh review then found and remediation covered a post-paste ambiguity: if Cmd+V was
sent but clipboard restoration failed, MicAI could previously offer a retry that
might paste twice. The coordinator now emits a distinct post-insertion restoration
error. Dictation/recovery treat it as a terminal uncertain outcome, while proof
approval becomes non-actionable **Check the original field** evidence and cannot
offer automatic retry. Focused tests cover one paste, failed restore, and no retry.
The same remediation assigns HUD mode on opposite-mode preflight rejection and
returns AI Command provider status to its configured idle value on cancellation.
