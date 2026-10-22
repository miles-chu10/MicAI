# HUD and resource budgets (plan)

Plan for steps 4 and 5 on `claude/project-thread-ren1b7`. Nothing here is
implemented yet. "Static" means provable by unit tests or code reading on this
branch; "Live" needs the app running on a Mac with permissions granted, which
waits for the signing decision and enough free disk.

## Current HUD (from main, kept by the merge)

`Sources/MicAI/HUD/` — `HUDModel` (published state), `RecordingHUDView` (pill
plus optional live-text bubble), `RecordingHUDController` (one nonactivating
borderless panel, 560 × 170 fixed so text never resizes the window, ignores the
mouse). Already present: mode glyph and tint, waveform, elapsed time,
"esc" hint while cancellable, "sent to ChatGPT" vs "on this Mac" while waiting,
Cancelled state, live partial text while recording (preview only, never
inserted).

## Step 4: compact HUD changes

1. **Destination badge from the first frame.** While recording, show where the
   result will go next: "Local" for plain dictation and on-device clean-up,
   "ChatGPT" for consented cloud clean-up and AI modes. Derive it in
   `AppModel.bindHUD()` from `settings.refinementRoute` and the operation's
   mode, so it cannot disagree with what the composer will do.
2. **Held-result state.** When `InsertionRecovery` keeps text, show a failure
   pill with two lines: the reason, then "Text kept · Paste Last Result".
   Today the full hint is appended to `errorMessage`, and the view's two-line
   limit can cut it off. Move the hint into a `HUDModel.keptText: Bool` flag
   and render it as its own line.
3. **Meter decoupled from layout.** `HUDModel.push(level:)` republishes an
   18-value array for every audio level. Throttle to at most 30 updates a
   second and stop pushing when the phase is not `.recording`.
4. **Accessibility.** Announce phase changes only, not level updates; respect
   Reduce Motion (no pulse, no waveform animation) and Reduce Transparency
   (solid background instead of `.ultraThinMaterial`).
5. **No focus theft.** Keep `.nonactivatingPanel`; the panel must never become
   key.

| Check | Kind |
| --- | --- |
| Badge text for each (mode, route) pair, as a pure function in MicAICore | Static |
| Held-result flag set only when `InsertionRecovery` kept text; never on cancel | Static |
| Meter throttle: 1,000 pushed levels in 1 s produce ≤ 30 publishes | Static |
| Panel never key; frontmost app unchanged after record, cancel, failure | Live |
| Screenshots of recording, waiting (local and ChatGPT), cancelled, held result | Live |
| VoiceOver announces phase changes only; Reduce Motion/Transparency honoured | Live |

## Step 5: budgets

Numbers are proposals until measured. Measurements record durations and
memory only, never audio or text.

### Audio

The accumulator stores samples at the input device's rate. At 48 kHz mono
Float32, the 120 s cap is about 23 MB, plus a 7.7 MB 16 kHz copy at stop.
Live preview copies the newest 20 s (about 3.8 MB at 48 kHz) and resamples it
every 800 ms.

| Budget | Value | Check | Kind |
| --- | --- | --- | --- |
| Max recording | 120 s (exists) | Capture stops at cap and reports it | Static |
| Accumulator | Reserve once at the cap; no growth past it | Capacity after 130 s of synthetic frames ≤ cap | Static |
| Preview cost | ≤ 1 preview pass in flight; skipped when nothing new | Overlap counter stays ≤ 1 (LivePreviewTests pattern) | Static |
| Buffers after stop/cancel | Released | Accumulator nil after stop and cancel | Static |
| Peak RSS during 120 s dictation | Measure, then set a ceiling | 30 runs, p95 recorded | Live |

### Speech model

`FluidAudioRecognizer` loads and keeps one `AsrManager` with no unload path.

| Budget | Value | Check | Kind |
| --- | --- | --- | --- |
| Unload | `unload()` when idle and no operation owns the model | Unload during an operation is refused | Static |
| Idle eviction | After a configurable idle window (start at 10 min) | Injected clock: evicts at window, not before | Static |
| Memory pressure | Evict on `.warning`/`.critical` when idle | Simulated pressure event evicts only when idle | Static |
| Cold vs warm | Report separately | Cold load time, warm 10 s utterance p50/p95 over 30 runs | Live |
| Idle footprint | Settled RSS with model unloaded vs loaded | Two samples after 60 s idle | Live |
| Microphone | Never open while idle to keep ASR warm | Capture state idle between operations | Static |

### Tokens and text

| Budget | Value | Check | Kind |
| --- | --- | --- | --- |
| Plain dictation | 0 model calls by default | `defaultSettingsMakeNoProviderCall` (exists) | Static |
| Calls per operation | ≤ 1, no automatic retry | Runner invocation count is 1 on success and failure | Static |
| Input size | 8,000 characters of selection, 2,000 of instruction | Oversized input rejected before the runner is called, with a "select less" message | Static |
| Output size | 4,000 characters; stdout capped at 256 KiB, stderr at 64 KiB (done: `CodexOutputLimits`) | Over the stdout cap fails as `llmOutputTooLarge` and stops the child; stderr past its cap is drained and dropped (`FoundationCodexCommandRunnerTests`) | Static |
| Context sent | Instruction and selection only; no history, screen or clipboard | Captured stdin has exactly the payload keys | Static |
| Usage | Input, cached input, output reported; unknown stays unknown | Existing `LLMUsageTests`, `CodexJSONParserTests` | Static |
| Timeout | 90 s (exists) | `timeoutMapsToServerFailure` (exists) | Static |

Character limits are product limits, not token counts. They are enforced
before `CodexCLIClient` spawns the CLI, so a rejected request costs nothing.
