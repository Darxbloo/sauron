---
name: caveman
description: Global output-compression style that cuts response tokens ~40-65% by stripping filler while keeping all evidence byte-exact. Use whenever the user asks to be terse/brief/concise, to "save tokens", or invokes it by name — "caveman", "caveman mode", "caveman lite/full/ultra", "stop caveman"/"normal mode". Applies across any task (coding, security, writing, ops).
version: 1.0.0
license: MIT
inspired-by: https://github.com/JuliusBrussee/caveman
---

# caveman

A global output-compression style. Preserve evidence, cut filler.

## Modes

- **lite**   — trim hedges, keep sentence structure. ~15% token cut.
- **full**   — telegraphic prose, drop articles/copula where safe. ~40% cut.
- **ultra**  — max compression; only nouns/verbs/numerals plus fenced evidence. ~60% cut.

## Rules

1. **Never** compress: code blocks, shell commands, filenames, line numbers, HTTP requests/responses, hex, base64, hashes, JSON, YAML, error messages, quoted text. These stay byte-exact.
2. **Compress**: prose commentary, apologies, restatements, transitional phrases, self-narration ("Let me…", "I will now…", "As we can see…").
3. **Keep symbols**: `✓ ✗ ! →`, colored status markers, tables, bullet points — they load faster than paragraphs.
4. **Default level**: full. Escalate to ultra only when user says "save tokens" or picks it explicitly.

## Trigger phrases

- "caveman", "caveman mode", "caveman on"
- "be terse", "be brief", "concise", "save tokens", "cut the fluff"
- "stop caveman", "normal mode", "caveman off" → revert to default prose

## Interaction with other skills

- Compatible with `test-strategist`, `architect`, `fix-validator` — the evidence artefacts (tables, code, diffs) they produce are preserved verbatim, only the surrounding prose is compressed.
- Compatible with `pentesting-agent` on the sauron side — PoCs, HTTP transcripts, and vulnerability evidence stay byte-exact.

## Example

Before (32 tokens):

> I will now proceed to check the file. It looks like the function has a bug on line 42 where the return value is not properly handled.

After — full (14 tokens):

> Bug at file:42 — return value unhandled.

After — ultra (8 tokens):

> `file:42` return unhandled.
