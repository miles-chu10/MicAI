# MicAI prototype acceptance ledger

Date: 2026-07-27

This ledger maps one-to-one to the seven acceptance criteria in
`docs/BRIEF.md`. `PASS` means the full criterion has direct evidence.
`UNVERIFIED-MANUAL` means implementation or partial automated evidence exists,
but the required target-machine journey has not been performed. No real
credential, permission, microphone, model-download, or target-app action was
used to prepare this ledger.

## BRIEF acceptance criteria

| # | Criterion | Status | Evidence and remaining boundary |
| --- | --- | --- | --- |
| 1 | A clean-clone `bash scripts/codex-build.sh` succeeds and produces `dist/MicAI.app`. | **UNVERIFIED-MANUAL** | The current worktree build passed on 2026-07-27 and produced a signed app with an arm64 executable, valid plist, `MicAI.icns`, macOS 14 minimum, and `LSUIElement=true`. A clean clone with a cold dependency cache was not created because this task is constrained to the current worktree. |
| 2 | Launch shows the menu-bar icon; onboarding requests Microphone access and explains Accessibility. | **UNVERIFIED-MANUAL** | The packaged process remained alive and CoreGraphics observed its 940×640 primary window. Source and build evidence cover `MenuBarExtra`, `LSUIElement`, and the five-step onboarding UI. The menu icon and fresh-preference/TCC denial-and-recovery journey were not exercised. Follow Manual runbook A. |
| 3 | Holding the dictation hotkey records; release transcribes locally with Parakeet and inserts into TextEdit within about two seconds for a 10-second utterance. | **UNVERIFIED-MANUAL** | The audio → local ASR → cleanup → exact-target guarded insertion path compiles and its fake-boundary tests pass. No model was downloaded, no audio was recorded, and no TextEdit or latency trial was performed. Follow Manual runbook B, including hold and toggle trials. |
| 4 | Selected text plus the spoken command “make this uppercase” replaces it using the configured provider. | **UNVERIFIED-MANUAL** | Request/auth/SSE behavior is fake-transport tested for both providers (OpenAI API key and ChatGPT subscription), including true incremental byte streaming, cancellation, timeout, early EOF, completion, and one 401 credential reload for the subscription provider. No credential contents were accessed and no authenticated request was made. Follow Manual runbook C. |
| 5 | Escape cancels recording without inserting anything. | **UNVERIFIED-MANUAL** | Core cancellation and stale-result suppression tests pass, and the HUD/cross-phase Esc path is wired. Real global Esc, recording, ASR wait, LLM wait, HUD focus, and zero-insertion behavior were not exercised. Follow Manual runbook D. |
| 6 | `bash scripts/codex-test.sh` passes MicAICore tests covering command routing, auth parsing, and injected clipboard restoration. | **PASS** | Final run on 2026-07-27 passed 79 tests in 13 suites. Existing suites include `CommandEngineTests`, `CodexAuthFileLoaderTests`, `TextInsertionCoordinatorTests`, and the new streaming client cases. |
| 7 | No secrets are stored in the repo; `dist/` and `.build/` stay absent from `git status`. | **PASS** | No credential was read, printed, copied, or modified. Settings serialization tests exclude secret/transient fields. `git status --short` showed source/workflow changes but no `.build/` or `dist/` artifacts; both remain ignored. The production credential path remains read-only runtime input. |

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
   Accessibility, the Parakeet speech model, and AI Commands. Confirm
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

1. In onboarding or Settings → Readiness, click **Prepare Local Model** or
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
   target.
6. Start another trial and press Escape before Cmd+V. Confirm zero insertion and
   clipboard restoration. Do not interpret Escape after text is already pasted
   as undo; that point is intentionally too late.

### C. First real AI Command

1. Obtain explicit approval immediately before this external call. Do not open
   or inspect any credential file or environment value.
2. For the default provider, launch MicAI with `OPENAI_API_KEY` set in its
   environment. In Settings, choose a command hotkey distinct from dictation,
   keep the provider on **OpenAI API key**, enter a supported model, save, and
   confirm AI Commands reports ready to attempt. To exercise the opt-in
   ChatGPT-subscription provider instead, select it in Settings and confirm the
   same readiness; do not open or inspect the credential file.
3. In TextEdit type `hello`, select it, hold the command hotkey, say
   “make this uppercase,” and release. Confirm the result is `HELLO`, replacement
   occurs once, and no partial/failed output is inserted.
4. Put the cursor on an empty line with no selection, hold the command hotkey,
   speak a short drafting instruction, and release. Confirm the completed result
   is inserted rather than routed as a replacement.
5. Record only provider status, SSE result classification, and pass/fail. If a
   route is rejected, stop; do not retry with credential experiments without a
   separate approval.

### D. HUD and Escape exercises

1. Focus TextEdit, close the primary MicAI window, and begin dictation. Confirm
   the floating HUD remains visible, does not activate MicAI, and never becomes
   the insertion target.
2. Exercise recording, transcribing, awaiting-LLM, inserting, cancelled, and a
   recoverable failure presentation where safely practical. Confirm the level
   meter moves during recording.
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

## Final automated validation

All four required scripts passed on 2026-07-27:

- `bash scripts/codex-test.sh`: PASS — 79 tests in 13 suites.
- `bash scripts/codex-typecheck.sh`: PASS — debug build completed.
- `bash scripts/codex-lint.sh`: PASS — strict format lint exited zero.
- `bash scripts/codex-build.sh`: PASS — release build assembled and ad-hoc
  signed `dist/MicAI.app`.
