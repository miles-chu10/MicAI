# MicAI

AI dictation for macOS that keeps your voice on your Mac.

Hold a key and speak, and polished text appears at the cursor in whatever app
you're using. Speech is recognised on the device by
[Parakeet](https://github.com/FluidInference/FluidAudio). The only thing that
ever goes over the network is text, and only when you use an AI feature.

## What it does

Four modes, each on its own keyboard shortcut:

| Mode | Default shortcut | What happens |
| --- | --- | --- |
| **Dictation** | Right ⌥ | Your words, cleaned up and written in the tone of the app you're in |
| **Command** | ⌃⌥Space | Select text and say how to change it: "make this friendlier" |
| **Translate** | ⌃⌥T | Translates the selection, or what you say, into your chosen language |
| **Ask AI** | ⌃⌥A | Questions open an answer window. Anything else is typed at the cursor |

Command, Translate and Ask AI are off until you turn them on in Settings.

Also included:

- **Vocabulary.** Corrections for names and jargon, applied on the Mac. Fix a
  line in History and MicAI learns the changed words.
- **Snippets.** Say a trigger phrase on its own and saved text goes in exactly
  as written.
- **Hold or tap.** Hold the key to talk, or tap it once to keep recording
  hands-free until you press it again.
- **Your rules.** Standing instructions such as "use British spelling", applied
  to every clean-up.
- **Live words.** See what MicAI heard above the recording HUD while you
  speak.
- **Clean-up on this Mac.** On macOS 26 with Apple Intelligence, clean-up can
  run on the device, even in privacy mode.
- **Privacy mode.** One switch that keeps everything on the Mac.
- **History and stats.** Everything MicAI typed, searchable and correctable,
  plus words dictated and time saved.

[docs/FEATURES.md](docs/FEATURES.md) compares all of this with Voiskey,
FluidVoice, VoiceInk, Wispr Flow and Superwhisper.

## Where your words go

| Stays on your Mac | Sent to the language model |
| --- | --- |
| Microphone audio, speech recognition, vocabulary, snippets, history, and clean-up when set to Apple Intelligence | The transcript for clean-up, plus the selected text for Command, Translate and Ask AI |

Two providers are supported:

- **ChatGPT subscription.** Uses the ChatGPT sign-in that the
  [Codex CLI](https://github.com/openai/codex) already stored on your Mac. MicAI
  reads it and never copies it.
- **OpenAI API key.** Saved in the macOS Keychain.

## Requirements

- macOS 14 or later on Apple silicon
- Microphone and Accessibility permission. First-run setup walks you through
  both.
- For the AI features: a ChatGPT subscription signed in through Codex, or an
  OpenAI API key

## Build

No Xcode project. Everything builds with Swift Package Manager:

```bash
bash scripts/codex-build.sh   # builds dist/MicAI.app and signs it ad hoc
bash scripts/codex-run.sh     # builds and opens it
bash scripts/codex-test.sh    # unit tests
bash scripts/codex-lint.sh    # swift format lint
```

CI builds, tests, packages and lint-checks every push on macOS
(`.github/workflows/ci.yml`).

## Project layout

```
Sources/MicAICore/   Speech, clean-up, modes, vocabulary, snippets, history, settings
Sources/MicAI/       The SwiftUI app: menu bar, HUD, Settings, History, setup
Tests/               Unit tests for MicAICore
scripts/             Build, run, test and lint entry points
docs/                Brief, PRD, spec, plan, acceptance criteria, feature research
```

`docs/BRIEF.md` is the product and engineering source of truth.
