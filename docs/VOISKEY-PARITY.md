# Voiskey parity — gap analysis and implementation notes

Status: AI/behavior layer implemented. Visual match to Voiskey's UI is **not**
done and is deliberately deferred (see "Open questions").

## How Voiskey's feature set was sourced

Voiskey.app could not be inspected directly. The implementation environment is a
Linux container with no macOS, no `/Applications`, and no display, and the
network egress policy blocks `voiskey.ai`, the App Store, and Product Hunt. The
feature list below comes from web search result summaries of Voiskey's own
marketing pages, not from running the app or reading its UI.

Consequence: **feature intent is grounded, visual design is not.** Every layout
decision in this change is conventional macOS design, not a copy of Voiskey.

Voiskey capabilities identified:

| Capability | Source characterization |
| --- | --- |
| Three hotkey modes | Dictation, AI Translate, and Ask AI, all driven from keyboard shortcuts |
| Context-aware output | Reads the destination app and tailors formatting, tone, and word choice |
| Disfluency clean-up | Catches fillers, stumbles, changes of mind, grammar slips |
| Learned vocabulary | Remembers names, jargon, spelling preferences after one correction |
| Cross-device vocabulary sync | Vocabulary follows you between devices |
| History | Kept on the user's own device under privacy mode |
| Privacy mode | Voice input not collected, not used for training |
| 100+ languages | Multilingual ASR |
| Input-level integration | Works in any text field rather than per-app |

## What was built

Local-first, per the architecture decision to keep Parakeet on-device ASR and
the ChatGPT-subscription OAuth client rather than adopt a backend.

### Context-aware output — `Sources/MicAICore/Style/`

`StyleTone` is a closed set of four registers (casual, professional, technical,
neutral), each expressed as prompt *constraints* rather than adjectives —
"do not add a greeting" survives a model swap where "be casual" does not.

`AppStyleResolver` maps the frontmost app to a tone, resolving in order: user
override, built-in bundle-identifier table, application-name keyword match,
configured default. The name fallback exists because bundle identifiers drift
between releases and distribution channels; the built-in table is best-effort
and every entry is user-correctable in Settings → Style.

### Disfluency clean-up — `Sources/MicAICore/Refinement/`

`RefinementEngine` sends the transcript through the LLM with
`ResponsesRequest.refinementInstructions`, a prompt whose every clause targets a
specific observed failure in this app class: answering the transcript instead of
rewriting it, inventing greetings, padding a one-line note into a paragraph.
The transcript is framed strictly as data, so a dictated "ignore your
instructions" ends up as text on screen rather than a behavior change.

Two guarantees shape the design:

1. **It never throws and never returns empty.** Network down, credential
   expired, model unavailable — the raw transcript still reaches the cursor.
   Degraded text beats lost text. Failures surface through
   `RefinementOutcome.failure` for the UI, and never block insertion.
2. **Output that grew past 3x the input is rejected** as the model having
   answered the transcript rather than rewritten it, with a 120-character floor
   so short utterances are not falsely flagged.

### Learned vocabulary — `Sources/MicAICore/Vocabulary/`

`VocabularyApplier` substitutes learned corrections **locally, before** the LLM
call. This ordering matters: a proper noun is correct even when refinement is
off, offline, or suppressed by privacy mode — and the model then sees the
corrected spelling rather than guessing at it. The same list is also passed as
prompt context so the model can fix inflections the word-boundary regex cannot.

`VocabularyLearner` derives corrections from an edit the user makes in History,
using an LCS word diff. It proposes only *replacement* blocks of three words or
fewer: insertions and deletions teach nothing about pronunciation, and long
blocks are rewording rather than a misheard term. Proposals are returned, not
auto-saved, so ordinary rewording does not fill the list with garbage.

### History — `Sources/MicAICore/History/`, `Sources/MicAI/Views/HistoryView.swift`

Capped, on-disk JSON in Application Support (not UserDefaults — it grows without
bound, and a corrupt defaults plist would take settings down with it). Records
both the raw transcript and the final text, so a later correction can be diffed
against what the recognizer actually heard. Covers AI Commands as well as
dictation, so "where did that text go" has one place to look.

### Privacy mode — `AppSettings.privacyMode`

A hard local-only switch: no refinement, no AI Commands. It *suppresses* rather
than edits `refinementEnabled` and `commandHotkey`, so turning it off restores
the user's previous configuration instead of making them set it up again.

### AI Translate — `Sources/MicAICore/Translate/`

With text selected, the selection is translated in place. With nothing selected,
what you say is translated and inserted. The target language is free text rather
than an enum: the model handles any language, and a fixed list would be
maintenance that silently caps the feature. Parakeet still recognizes English on
device, so dictated input is English — but a *selection* can be any language,
which makes inbound translation work too.

### Ask AI — `Sources/MicAICore/Ask/`

Ask a question and the answer opens in a window; say something that is not a
question and it is typed at the cursor. Routing is `AskIntentClassifier`, a local
heuristic (trailing `?`, or a leading interrogative), **not** a model call: it
decides whether text lands in the user's document, so it has to be predictable
across identical utterances. A model that classified the same sentence
differently on two presses would make the hotkey feel broken.

The routing is deliberately asymmetric. The `askAlwaysOpensWindow` preference can
only ever *force* the window; nothing routes an answer to the cursor against the
classifier. A wrong window costs a glance, a wrong insertion overwrites what the
user was writing.

Ask reads the selection as context and never replaces it — asking "what does this
regex do" must not overwrite the regex. That is why
`CommandPipeline.finish` is generic in its result rather than always returning an
`InsertionIntent`.

The answer window offers Copy rather than "Insert at cursor": by the time it is
open it owns the focus, so inserting would mean reactivating the previous app and
synthesising a paste into a target the user may have already left.

### Orchestration — `DictationComposer`

One place that owns the post-transcription ordering — vocabulary, then tone,
then refinement, then history — so the guarantees hold regardless of which UI
calls it.

## Deliberate divergences from Voiskey

| Voiskey | MicAI | Why |
| --- | --- | --- |
| Cross-device vocabulary sync | Local file only | Requires a backend and accounts; breaks the local-first premise in `docs/BRIEF.md` |
| 100+ languages | Parakeet TDT v2 (English) | Swapping ASR is a separate decision, tracked as P1 in the BRIEF |
| Cloud ASR | On-device Parakeet | Existing architecture; audio never leaves the Mac |

`VocabularyStore` and `TranscriptHistoryStore` are actors behind narrow
interfaces, so adding a sync backend later does not require a rewrite.

## Verification status

Verified by CI on a macOS runner (`.github/workflows/ci.yml`): the package
compiles, 162 tests pass, `dist/MicAI.app` builds and codesigns, and the build
leaves the working tree clean. That covers acceptance criteria 1, 6 and 7 in
`docs/BRIEF.md`.

CI has caught four real defects that reading the code did not:

1. `VocabularyEntry.isUsable` compared an entry's two sides case-INSENSITIVELY,
   so `"slack"` -> `"Slack"` was discarded as a no-op. Capitalizing a proper noun
   the recognizer lowercased is the most common correction the feature exists to
   make, so the filter was rejecting its primary use case.
2. `cancelActiveOperation` held a second switch over the operation mode that the
   AI Translate / Ask AI refactor missed: it called a renamed method and was no
   longer exhaustive.
3. `AskIntentClassifier` stripped only the ASCII apostrophe, so a transcript
   using the typographic one would have routed "what's ..." to the cursor
   instead of the answer window.
4. `AppSettings.validated` reported a missing translation language when the real
   problem was two modes bound to the same chord, sending the user to fix the
   wrong field. Structural checks now run first.

**CI cannot verify the product.** Criteria 2-5 -- onboarding and permissions,
hold-to-dictate landing text at the cursor within ~2s, a spoken command
replacing a selection, Esc cancelling cleanly -- all need a human at a Mac. A
runner has no microphone, cannot grant Accessibility, and never downloads the
Parakeet model. Green CI here means "it compiles and the units behave", not
"dictation works".

## Open questions

1. **UI fidelity.** The HUD, Settings, History, and onboarding layouts are
   conventional macOS design, not a match to Voiskey. Screenshots of Voiskey's
   HUD, settings, history panel, and onboarding are needed to close this. A
   rendering of the current screens, built from the SwiftUI source, is at
   https://claude.ai/artifact/33hnKKRpwZXnfzGM5Rh7go
2. **The Ask AI answer window is unverified.** It is raised from the
   `MenuBarExtra` label, the only always-instantiated view in a menu-bar-only
   app and therefore the only place that can observe an answer arriving and still
   reach `openWindow`. CI cannot exercise it; try it first in the manual pass.
3. **`AskIntentClassifier` will misfire on phrasings not in its table.** The
   interrogative list is fixed. Routing errors are safe in one direction only
   (toward the window), but a question phrased unusually will be typed at the
   cursor.
4. **HUD tone badge.** Showing the resolved tone live during recording is one of
   the more distinctive context-aware affordances, but it is a visual decision;
   `AppModel.lastTone` is published and ready to bind once the design is settled.
5. **Bundle identifier accuracy.** Several entries in
   `AppStyleResolver.builtInBundleTones` are best-effort and unverified on a real
   Mac — notably Cursor, the ChatGPT desktop app, Claude desktop, and Notion. The
   name-keyword fallback covers a wrong identifier, and users can override, but
   the table is worth checking against real `NSRunningApplication` values.
6. **Refinement cost and latency.** Clean-up adds a network round trip to every dictation.
   Whether that is acceptable, or should be gated to longer utterances, needs
   real-world measurement.
