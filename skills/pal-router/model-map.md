# PAL Model Map

**groq** (openai/gpt-oss-120b). I use this for report writing, vulnerability explanations, and skeptical validation. Hard cap of 8,000 tokens per minute, roughly 500 requests per minute. Aliases: `groq`, `gpt-oss-120b`, `gpt-oss`. Failure modes: truncates on long outputs; single-shot payloads of ~23,628 tokens fail outright, so split work into per-item calls.

**qwen3** (`qwen/qwen3.8-27b` via Groq). DEFAULT tool-executor for `/tools` and `pal run`: it emits clean `<tool_call>` output. Override with `PAL_CHAT_TOOLS_MODEL`. Failure mode it avoids: **gpt-oss trips Groq's output parser on tool-calling prompts (400 `output_parse_failed`)**, so keep gpt-oss for prose and qwen3 for tool loops. Shares the Groq key (`CUSTOM_API_KEY`) with `groq`.

**nemotron** (nvidia/nemotron-3.5-lightning:free via OpenRouter). I use it for bulk reading of large files such as JavaScript bundles, log dumps, and OpenAPI specs. 1M token context. Alias: `nemotron`. Failure mode: hallucinates on strict structured extraction. In one run it produced a random math-sum ramble instead of the requested index. Do not use it for byte-exact structured output.

**grok-4.1-fast** (x-ai via OpenRouter, 2M context). Permissive high-context security reasoning; the go-to fallback when Gemini refuses recon or attack-surface prompts. No observed refusals for authorized security work.

**flash** (gemini-3.6-flash, 1M context, alias `flash`). Fast structured extraction. Failure mode: refuses recon-log and attack-surface analysis for named targets, even under authorized scope. Route around it with `jq`/local or grok-4.1-fast.

**or-free** (openrouter/free meta-router, 200K context). Generalist fallback and quick summarization when nothing more specialised is available.

**pro** (gemini-3.1-pro-preview, 1M context, alias `pro`). Deep reasoning and adversarial debate through `mcp__pal__challenge`. Excels at multi-turn argumentation.

## Routing constraints

- **Authorization preamble.** When the classifier tags a task `security_permissive`, pal prepends an AUTHORIZATION preamble so groq/qwen3 stop refusing authorized recon, enum, and scan work. It complements (does not replace) the "gemini refuses, go to grok" failover.
- **Groq ITPM ≈ 7000.** The tool loop trims accumulated context to `PAL_TOOLS_CTX_CHARS` (default 16000) so each request fits. Keep tool-loop prompts small; chunk anything bigger.

## Delegation via `pal run`

`pal run "<task>"` is the headless one-shot: it runs the task with local tools and prints only the result.

- `--ro` read-only tools; `--agent` full Claude Code agent (`--agent-role autonomous|edit|plan|review`); `--model <m>`; `--max-steps N`; `--json` (task/mode/model/tools_used/result).
- `--plan <file>` runs every step of a plan file. Strongest handoff: write the plan to a file, run it, collect the result, do not babysit.
- Heavy coding/tool work: `pal run --agent`; use `--agent-role autonomous` when it must run git/gh/network unattended.

## Failover order for the common tasks

- **Deterministic recon parsing** (hosts, CNAMEs, params from JSONL): `jq` and local shell first (token-free, cannot refuse), then `grok-4.1-fast` if LLM reasoning is needed.
- **Structured extraction from prose**: `flash`, fallback `grok-4.1-fast`, avoid `nemotron`.
- **Report writing / skeptical validation**: `groq`, fallback `grok-4.1-fast`.
- **Bulk reading of very large files**: `nemotron`, fallback `or-free`.
- **Deep adversarial reasoning**: `pro`, fallback `groq`.
