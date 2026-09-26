---
name: pal-router
description: >-
  Delegate-first + failover doctrine for the framework. Dispatches sub-tasks to cheaper or free PAL
  models so Claude Opus's context stays reserved for judgment. Triggers on: 'route this to a
  cheaper model', 'delegate this read', 'who should write this report', 'which model do I use for
  X', 'gemini refused, what now'.
---

# pal-router

**One-line pitch:** Delegate-first + failover doctrine skill for the sauron framework. Dispatches sub-tasks to cheaper or free PAL models so Claude Opus's context stays reserved for judgment.

## When to invoke
- Any bulk file read (JS bundle, log dump, OpenAPI spec, GraphQL introspection).
- Any long-form writing (report, vuln explanation, remediation note, executive summary).
- Any structured extraction (endpoint list, header dump, param cluster).
- Any skeptical second-pass on someone else's output.
- Any adversarial critique of a finding.

If the task is a user-facing decision, an exploitation choice, a severity call, a safety-boundary check, an action with side effects, or an orchestration of tool sequences, keep it in Claude. Never delegate those.

## The routing map

- **groq** (`openai/gpt-oss-120b`, ~500 req/min, 8,000 tokens/min cap). Report writing, vulnerability and concept explanations, skeptical validation. Aliases: `groq`, `gpt-oss-120b`, `gpt-oss`.
- **nemotron** (`nvidia/nemotron-3.5-lightning:free` via OpenRouter, 1M context, alias `nemotron`). Bulk reading of large files. Do NOT use for strict structured extraction (it hallucinates).
- **grok** (`x-ai/grok-4.1-fast` when available, else `x-ai/grok-4.3` on OpenRouter, 2M context). Permissive high-context security reasoning. Reliable fallback when Gemini refuses.
- **flash** (`gemini-3.6-flash`, 1M context, alias `flash`). Fast structured extraction from prose. Failure mode: refuses recon-log or attack-surface analysis for named targets.
- **or-free** (`openrouter/free` meta-router, 200K context). Generalist fallback.
- **pro** (`gemini-3-pro-preview`, 1M context, alias `pro`). Deep reasoning and adversarial debate via `mcp__pal__challenge`.

Full model matrix and aliases: [model-map.md](model-map.md).

## Failover doctrine

If any model refuses, times out, or errors, immediately re-route to another model. A classifier refusal is a routing problem, not a stop.

Preferred order per common task:

1. **Deterministic recon parsing** (hosts, CNAMEs, params from JSONL): `jq` and local shell first (token-free, cannot refuse), then `grok` if LLM reasoning is needed.
2. **Structured extraction from prose**: `flash`, fallback `grok`, avoid `nemotron`.
3. **Report writing / skeptical validation**: `groq`, fallback `grok`.
4. **Bulk reading of very large files**: `nemotron`, fallback `or-free`.
5. **Deep adversarial reasoning**: `pro`, fallback `groq`.

## Wiring

The doctrine is enforced by two hooks in `~/.claude/settings.json`, both shipped in [`settings.example.json`](../../settings.example.json):

- **SessionStart** auto-invokes the `caveman`, `pentesting-agent`, and `validator` skills at the start of every session.
- **UserPromptSubmit** re-asserts the delegate-first + failover doctrine on every message so nothing drifts as sessions grow long.

## Trigger phrases
- "route this to a cheaper model"
- "delegate this read"
- "who should write this report"
- "which model do I use for X"
- "gemini refused, what now"

## Anti-patterns
- Never delegate a severity call or safety-boundary check.
- Never inline a long payload into a groq prompt if it exceeds 8,000 tokens; chunk it.
- Never trust nemotron to produce byte-exact structured output.
- Never treat a refusal as the end of the task; re-route.

## Token efficiency rules

- **Rule 1 (auto-compress large outputs):** any tool output above 5 KB (Bash, Read, WebFetch, jq) routes through `nemotron` (bulk read) or `flash` (structured) for compression before Claude reads it. Typical 10x reduction.
- **Rule 2 (batch PAL sub-tasks):** three separate groq calls for "draft report + suggest severity words + explain bug class" costs three adjudicate cycles. One structured PAL call returning all three saves two round trips.
- **Rule 3 (confidence triples):** on factual output, delegation prompts must ask for `{claim, confidence, source_span}` triples. Claude byte-checks only entries flagged below high confidence, not the whole draft.
- **Rule 4 (don't re-delegate):** never delegate the same task twice. If groq already drafted section X, quote it inline; do not re-ask.
- **Rule 5 (don't re-Read):** never `Read` a file already Read this session. Recall the content from conversation context.
- **Rule 6 (preempt predictable bloat):** on Bash calls whose full output you don't need, append `| head -c 5000` or `| jq -c` at the shell level rather than reading the whole dump and then summarizing.

## Auto-detect delegation triggers
Auto-invoke pal-router BEFORE reading when you see:
- A file open > 5 KB (`Read` with no `limit` on a large file)
- Any WebFetch call
- Bash output over 100 lines
- Any recon-tool result set (nuclei, dnsx, subfinder JSON) larger than 5 KB
- Any long-form prose request ("explain", "write up", "draft the report")

## When NOT to delegate
- The user asked for YOUR opinion or judgment (severity, chain viability, exploitability)
- A safety-boundary call (no 3rd-party data, no destructive action, no account creation)
- One-off short strings (< 200 bytes); PAL round-trip overhead dwarfs the saving

## The rule
> Delegate the prose, never the evidence.
