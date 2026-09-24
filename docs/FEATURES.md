# Features, and where they came from

MicAI takes its feature set from the AI dictation apps people actually compare
it with: Voiskey, FluidVoice, VoiceInk, Wispr Flow and Superwhisper. The rule
for borrowing a feature is that it has to fit a local-first app. Speech is
recognised on the Mac, there's no account and no MicAI server, and the only
network call is the one you choose to make to a language model.

## How the research was done

None of these apps could be run while this was written, because the build
environment is Linux with no macOS. The Voiskey, Product Hunt and review sites
were also blocked by its network policy. What each app does comes from its own
README or help pages, or from search summaries of its marketing pages. The table
records what those sources say, not what was observed in the app. MicAI's design
is its own, not a copy of any of these.

## The comparison

| Feature | Seen in | MicAI |
| --- | --- | --- |
| Speech recognised on the device | FluidVoice, VoiceInk, Superwhisper | Yes. Parakeet TDT v2 (English) or v3 (25 languages) |
| Removes fillers and false starts | All five | Yes. Clean-up, with the raw words kept if the model fails |
| Tone or prompt that follows the app | Voiskey, FluidVoice, VoiceInk (Power Mode), Superwhisper | Yes. Four tones, per-app overrides, and your own rules |
| Rewrite selected text by voice | FluidVoice (Write Mode), Wispr Flow (Command Mode), Superwhisper | Yes. Command |
| Translate as you dictate | Voiskey | Yes. Translate, into any language the model knows |
| Ask an assistant | Voiskey, VoiceInk | Yes. Ask AI. Questions open a window, anything else is typed |
| Personal dictionary | Voiskey, VoiceInk, Wispr Flow, Superwhisper | Yes. Vocabulary, applied on the Mac before the model |
| Learns from your corrections | Voiskey, Wispr Flow | Partly. It learns from edits in History, not from typing in other apps |
| Snippets you trigger by voice | Wispr Flow | **New.** Say the trigger on its own and the saved text goes in |
| Hands-free recording | Wispr Flow (double-tap) | **New.** "Hold or tap": tap once to keep recording |
| Many spoken languages | Voiskey (100+), FluidVoice (up to 99) | **New, partly.** 25 European languages with the multilingual model |
| Your own standing instructions | Superwhisper (custom modes) | **New.** "Your rules" in Settings › Style |
| Usage stats | FluidVoice | **New.** Words, time saved and speaking rate, from history |
| Choice of AI provider | FluidVoice, VoiceInk | **New.** ChatGPT subscription or an OpenAI API key in the Keychain |
| Sounds on start and finish | Common across the category | **New** |
| Paste the last result again | Common across the category | **New.** Menu bar › Paste Last Result |
| Live words while you speak | FluidVoice | **New.** A rough transcript above the HUD, refreshed about every 0.8 s |
| AI clean-up with no network | FluidVoice (Fluid-1) | **New.** Apple Intelligence on macOS 26, which also works in privacy mode |
| Reads the screen or clipboard | VoiceInk, Superwhisper | No, by choice. MicAI reads the selection only when a mode needs it |
| Keeps audio recordings | FluidVoice | No, by choice. Audio is never written to disk |
| Controls the Mac by voice | FluidVoice (Command Mode) | No. Out of scope for a dictation app |
| Syncs across devices | Voiskey | No. It would need a server and an account |

## Why some things are left out

- **Screen and clipboard context.** Reading the screen makes answers better,
  but it also means sending whatever is visible to the model. MicAI's promise is
  that only the transcript and, for the AI modes, the text you selected ever
  leave the Mac. That's easy to explain, and it doesn't hold if the screen goes
  along too.
- **Sync.** Vocabulary, snippets and history are local JSON files, one actor
  each behind a narrow interface. Sync could sit behind those later without a
  rewrite, but it needs infrastructure this project doesn't have.
- **Audio history.** The history keeps text, which is enough to correct and
  learn from. Keeping audio would make the history far more sensitive for
  little gain.

## How live words and on-device clean-up work

**Live words.** While you record, MicAI transcribes the newest 20 seconds of
audio about every 0.8 seconds, using the Parakeet model that's already loaded,
and shows the result above the HUD. It's a preview only. When you stop, the
whole recording is transcribed again in one pass, and that's the text that gets
inserted. The preview pass is always finished before the final one starts,
because the two share the recognizer. Capping the preview at 20 seconds keeps
its cost flat however long you talk. FluidAudio also has a streaming model, but
it would be a second download and is English-only, whereas this approach works
with either Parakeet model.

**On-device clean-up.** Settings › Style › "Clean up with" can use Apple
Intelligence instead of your language model. It uses the same instructions,
tone, vocabulary and rules, and runs through Apple's Foundation Models framework
on the Mac. Because nothing leaves the Mac, it keeps working in privacy mode. If
Apple Intelligence is off or this Mac can't run it, your words go in as spoken
and the HUD says why. MicAI never quietly switches to the network. The framework
is weak-linked, so MicAI still launches on macOS 14 and 15.

## Next

1. Custom modes: a named prompt with its own shortcut, generalising Command,
   Translate and Ask AI.
2. Command, Translate and Ask AI on the on-device model too, so they also work
   in privacy mode.

## Sources

- Voiskey: [voiskey.ai](https://www.voiskey.ai/), and the
  [launch announcement](https://en.prnasia.com/releases/global/voiskey-officially-launches-the-first-ai-voice-typing-app-focused-on-expression-intelligence-540095.shtml)
- FluidVoice: [README](https://github.com/altic-dev/FluidVoice)
- VoiceInk: [README](https://github.com/beingpax/VoiceInk)
- Wispr Flow: [Command Mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode),
  [hands-free](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free)
- Superwhisper: [custom modes](https://superwhisper.com/docs/modes/custom)
- Product Hunt: [AI dictation apps](https://www.producthunt.com/categories/ai-dictation-apps)
