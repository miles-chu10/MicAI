# Prompt caching measurements

MicAI uses `codex exec --ephemeral --json` for AI text tasks. Only a completed
turn's final assistant message becomes text to insert, with the client's existing
surrounding-whitespace trimming. Usage stays separate in
`LocalMetrics.languageModelReports`, alongside task, route, requested model and
duration. Reports remain in memory for the current app session (up to 50); they
contain no prompts, transcripts, output, credentials or session identifiers.

The Codex JSON completion reports input, cached input and output tokens. A blank
model override inherits the user's existing Codex default; the actual model is
unknown unless the provider reports it. Missing or malformed counts are unknown,
including cache writes when the CLI does not expose them. Cache counts that
exceed known input, individually or together, also become unknown. The unused direct
Responses clients also retain optional completion usage and response model
through their callbacks, including `input_tokens_details.cache_write_tokens` when
provided. Neither sets a random per-operation `prompt_cache_key`.
The API-key and ChatGPT subscription clients report distinct routes; neither is
wired into the app's current CLI path by this change.

Cache read and write counts are portions of input tokens, not extra tokens to
add to the total. Reported counts alone do not establish cost or latency savings,
and API prices do not establish ChatGPT subscription usage savings. No live
cache measurements have been made by the synthetic parser tests. These changes
do not force a model, add cache options or retention, or pad prompts.

Older settings that selected a known transcription-only model for AI text tasks
migrate only that override to blank. New such entries show a settings validation
error; custom text model IDs remain available for Codex to validate. The separate
audio model setting and default local Parakeet dictation are unchanged.

Sources: [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode),
[prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching),
[GPT-Transcribe endpoints](https://developers.openai.com/api/docs/models/gpt-transcribe),
[file transcription models](https://developers.openai.com/api/docs/guides/speech-to-text).
