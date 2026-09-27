#!/usr/bin/env bash
# sauron - interactive setup.
# Lets you pick which Hermes models to enable and whether the hooks install
# globally (~/.claude/settings.json) or per-project (./.claude/settings.json).
# Writes only what you approve. Backs up any existing settings first.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- pretty print ----------
BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*"; }
hd()   { printf '\n%s%s%s\n' "$BOLD" "$*" "$RST"; }

command -v jq >/dev/null || { err "jq is required (apt install jq)"; exit 1; }

# ---------- banner ----------
# ANSI 256 palette for the fire look:  208 = bright orange, 214 = amber, 220 = gold
ORG=$'\033[38;5;208m'; AMB=$'\033[38;5;214m'; GLD=$'\033[38;5;220m'; EMB=$'\033[38;5;202m'
printf '\n'
printf '%s              .-~~~-.               %s\n'                   "$RED" "$RST"
printf '%s            .%s(   %so   %s).%s              %s\n'  "$RED" "$GLD" "$EMB" "$GLD" "$RED" "$RST"
printf '%s             ~-...-~                %s\n'                   "$RED" "$RST"
printf '\n'
printf '%s     ███████╗ █████╗ ██╗   ██╗██████╗  ██████╗ ███╗   ██╗%s\n' "$ORG" "$RST"
printf '%s     ██╔════╝██╔══██╗██║   ██║██╔══██╗██╔═══██╗████╗  ██║%s\n' "$ORG" "$RST"
printf '%s     ███████╗███████║██║   ██║██████╔╝██║   ██║██╔██╗ ██║%s\n' "$AMB" "$RST"
printf '%s     ╚════██║██╔══██║██║   ██║██╔══██╗██║   ██║██║╚██╗██║%s\n' "$AMB" "$RST"
printf '%s     ███████║██║  ██║╚██████╔╝██║  ██║╚██████╔╝██║ ╚████║%s\n' "$GLD" "$RST"
printf '%s     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝%s\n' "$GLD" "$RST"
printf '\n'
printf '%s          %sinteractive setup%s   %s.%s   one agent to route them all%s\n' "$DIM" "$BOLD" "$RST$DIM" "$AMB" "$RST$DIM" "$RST"
printf '\n'

# ---------- 0. orchestrator ----------
hd "0. Which agent orchestrator do you use?"
cat <<EOF
  ${CYN}c${RST}) claude-code    (default)   full: hooks + Skill() invocations + delegate policy
  ${CYN}r${RST}) cursor                     writes .cursor/rules/FRAMEWORK.mdc (alwaysApply)
  ${CYN}l${RST}) cline                      writes .clinerules with the delegate policy
  ${CYN}x${RST}) codex-cli (OpenAI)         writes ~/.codex/instructions.md
  ${CYN}a${RST}) aider                      writes .aider.conf.yml + FRAMEWORK.md conventions
  ${CYN}g${RST}) generic / other            writes SYSTEM_PROMPT.md you paste into any tool
EOF
read -rp "choice [c/r/l/x/a/g] (default: c): " ORCH
ORCH="${ORCH:-c}"
case "$ORCH" in
  c|r|l|x|a|g) ok "orchestrator: $ORCH" ;;
  *) err "invalid orchestrator"; exit 1 ;;
esac

# ---------- 1. scope ----------
hd "1. Where should it install?"
cat <<EOF
  ${CYN}g${RST}) global      → ~/.claude/settings.json         (loads every session, every project)
  ${CYN}p${RST}) per-project → \$PWD/.claude/settings.json      (only loads when Claude Code runs here)
  ${CYN}s${RST}) skip        → print the settings JSON to stdout, do not write anything
EOF
read -rp "choice [g/p/s] (default: p): " SCOPE
SCOPE="${SCOPE:-p}"
case "$SCOPE" in
  g|p) TARGET="" ;;  # resolved later, after we know both ORCH and SCOPE
  s)   TARGET="" ;;  # dry-run: no write
  *)   err "invalid scope"; exit 1 ;;
esac
[ "$SCOPE" = "s" ] && ok "target: stdout (dry run)"

# ---------- 2. skill auto-load ----------
hd "2. Which skills should auto-load at session start?"
say "  These are invoked as the very first tool calls of every session."
say "  Leave blank to skip a skill; type y to include it."
prompt_yn () { local q="$1" d="$2" a; read -rp "  $q [Y/n]: " a; a="${a:-$d}"; case "$a" in y|Y) echo "1" ;; *) echo "0" ;; esac; }
S_CAVE=$(prompt_yn "caveman (full compression, byte-exact evidence)" y)
S_PENT=$(prompt_yn "pentesting-agent (offensive-security playbooks)" y)
S_VALI=$(prompt_yn "validator (preload skeptical QA reviewer)" y)

# ---------- 3. models ----------
hd "3. Which Hermes models should be listed in the delegate-first policy?"
say "  Pick every model your Hermes install actually has keys for."
say "  Unselected models are dropped from the routing map so Claude never tries them."
M_GROQ=$(prompt_yn "groq (openai/gpt-oss-120b) - report writing, validation" y)
M_NEMO=$(prompt_yn "nemotron (nvidia via OpenRouter) - bulk reading, 1M ctx" y)
M_GROK=$(prompt_yn "grok (x-ai via OpenRouter, 2M ctx) - permissive security reasoning" y)
M_FLSH=$(prompt_yn "flash (gemini-3.6-flash) - structured extraction" y)
M_ORFR=$(prompt_yn "or-free (openrouter meta-router) - generic fallback" y)
M_PRO=$(prompt_yn "pro (gemini-3-pro-preview) - adversarial debate" y)

# guard: warn if user selected nothing (both no skills AND no models)
if [ "$S_CAVE" = 0 ] && [ "$S_PENT" = 0 ] && [ "$S_VALI" = 0 ] && \
   [ "$M_GROQ" = 0 ] && [ "$M_NEMO" = 0 ] && [ "$M_GROK" = 0 ] && \
   [ "$M_FLSH" = 0 ] && [ "$M_ORFR" = 0 ] && [ "$M_PRO" = 0 ]; then
  warn "you selected no skills and no models; the hook would be inert."
  read -rp "  proceed anyway and write an empty hook? [y/N]: " a
  case "${a:-n}" in y|Y) : ;; *) err "aborted, nothing written"; exit 1 ;; esac
fi

# build a compact routing sentence based on selections
ROUTING=""
[ "$M_GROQ" = 1 ] && ROUTING+="groq (gpt-oss-120b, ~500 rpm, 8000 tpm cap) for report writing, vuln explanations, and skeptical validation. "
[ "$M_NEMO" = 1 ] && ROUTING+="nemotron (nvidia, 1M ctx) for bulk reading of large files. "
[ "$M_GROK" = 1 ] && ROUTING+="grok (x-ai, 2M ctx) for permissive high-context security reasoning when Gemini refuses. "
[ "$M_FLSH" = 1 ] && ROUTING+="flash (gemini-3.6-flash, 1M ctx) for fast structured extraction. "
[ "$M_ORFR" = 1 ] && ROUTING+="or-free (OpenRouter meta-router, 200K ctx) as generalist fallback. "
[ "$M_PRO" = 1 ]  && ROUTING+="pro (gemini-3-pro-preview) for deep-reasoning fallback and adversarial debate via mcp__hermes__challenge. "
[ -z "$ROUTING" ] && ROUTING="(no Hermes models selected; delegate-first policy inactive). "

# build skills list
SKILLS_LIST=""
[ "$S_CAVE" = 1 ] && SKILLS_LIST+="\`caveman\` (full mode), "
[ "$S_PENT" = 1 ] && SKILLS_LIST+="\`pentesting-agent\`, "
[ "$S_VALI" = 1 ] && SKILLS_LIST+="\`validator\` (preload), "
SKILLS_LIST="${SKILLS_LIST%, }"

# ---------- 4. render SessionStart + UserPromptSubmit hook bodies ----------
# Full doctrine and routing map live in CLAUDE.md (auto-loaded, prompt-cacheable).
# Hooks stay lean and just name the preloaded skills + the pointer.
if [ -n "$SKILLS_LIST" ]; then
  SS_TEXT="Doctrine + routing map are in CLAUDE.md at the project root (already loaded). Preload skills now: ${SKILLS_LIST}."
else
  SS_TEXT="Doctrine + routing map are in CLAUDE.md at the project root (already loaded)."
fi

UPS_TEXT="Doctrine active from CLAUDE.md. Delegate + failover. Batch Hermes calls."

# ---------- 5. build settings.json ----------
# Each hook fires: printf '%s\n' '<inline JSON with additionalContext>'
build_cmd () {
  local event="$1" text="$2"
  # produce the exact command string, with double-quotes inside additionalContext escaped for JSON
  local escaped
  escaped=$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf "printf '%%s\\n' '{\"hookSpecificOutput\":{\"hookEventName\":\"%s\",\"additionalContext\":\"%s\"}}'" "$event" "$escaped"
}
SS_CMD=$(build_cmd "SessionStart" "$SS_TEXT")
UPS_CMD=$(build_cmd "UserPromptSubmit" "$UPS_TEXT")
JSON=$(jq -n --arg ss "$SS_CMD" --arg ups "$UPS_CMD" '{
  hooks: {
    SessionStart:     [ { hooks: [ { type: "command", command: $ss  } ] } ],
    UserPromptSubmit: [ { hooks: [ { type: "command", command: $ups } ] } ]
  }
}')

# ---------- 6. write or dry-run ----------
if [ "$SCOPE" = "s" ]; then
  hd "config (dry run - copy manually):"
  case "$ORCH" in
    c) echo "$JSON" ;;
    *) printf '# SessionStart-equivalent\n%s\n\n# UserPromptSubmit-equivalent\n%s\n' "$SS_TEXT" "$UPS_TEXT" ;;
  esac
  exit 0
fi

# ---------- 5. resolve TARGET based on orchestrator + scope ----------
case "$ORCH" in
  c) case "$SCOPE" in
       g) TARGET="$HOME/.claude/settings.json" ;;
       p) TARGET="$PWD/.claude/settings.json" ;;
     esac ;;
  r) case "$SCOPE" in
       g) TARGET="$HOME/.cursor/rules/sauron.mdc" ;;
       p) TARGET="$PWD/.cursor/rules/sauron.mdc" ;;
     esac ;;
  l) case "$SCOPE" in
       g) TARGET="$HOME/.clinerules" ;;
       p) TARGET="$PWD/.clinerules" ;;
     esac ;;
  x) TARGET="$HOME/.codex/instructions.md" ;;
  a) case "$SCOPE" in
       g) TARGET="$HOME/.aider.sauron.md" ;;
       p) TARGET="$PWD/.aider.sauron.md" ;;
     esac ;;
  g) case "$SCOPE" in
       g) TARGET="$HOME/SYSTEM_PROMPT.sauron.md" ;;
       p) TARGET="$PWD/SYSTEM_PROMPT.sauron.md" ;;
     esac ;;
esac

hd "Ready to write ${TARGET}"
say "  Existing file will be backed up with .bak.<timestamp> suffix."
read -rp "proceed? [y/N]: " GO
[[ "$GO" =~ ^[yY]$ ]] || { warn "aborted, nothing written"; exit 0; }

mkdir -p "$(dirname "$TARGET")"
if [ -f "$TARGET" ]; then
  BAK="${TARGET}.bak.$(date +%s)"
  cp "$TARGET" "$BAK"
  ok "backup: $BAK"
fi

# ---------- 6. write in the format for the chosen orchestrator ----------
case "$ORCH" in
  c)
    # Claude Code: merge JSON hooks (preserve existing, dedup identical)
    if [ -f "$TARGET" ]; then
      jq --argjson add "$JSON" '
        def dedupe(cur; added):
          (cur // []) as $c
          | (added // []) as $a
          | $c + ($a | map(select(. as $new | $c | map(.hooks[0].command // "") | index($new.hooks[0].command // "") | not)));
        . as $orig
        | ($orig * ($add | del(.hooks)))
        | .hooks.SessionStart     = dedupe($orig.hooks.SessionStart;     $add.hooks.SessionStart)
        | .hooks.UserPromptSubmit = dedupe($orig.hooks.UserPromptSubmit; $add.hooks.UserPromptSubmit)
      ' "$TARGET" > "${TARGET}.tmp" && mv "${TARGET}.tmp" "$TARGET"
      ok "merged into $TARGET (existing hooks preserved, sauron hooks appended)"
    else
      echo "$JSON" | jq . > "$TARGET"
      ok "wrote $TARGET"
    fi
    ;;
  r)
    # Cursor: .mdc rules file with frontmatter alwaysApply:true
    cat > "$TARGET" <<MDC
---
description: sauron framework - delegate-first + failover doctrine
alwaysApply: true
---

# sauron rules

## Session context (equivalent to Claude Code SessionStart)
$SS_TEXT

## Every-message reminder (equivalent to Claude Code UserPromptSubmit)
$UPS_TEXT
MDC
    ok "wrote Cursor rules: $TARGET"
    ;;
  l)
    # Cline: .clinerules plain markdown at project root or home
    cat > "$TARGET" <<CLR
# sauron rules for Cline

## Doctrine
$SS_TEXT

## On every message
$UPS_TEXT
CLR
    ok "wrote Cline rules: $TARGET"
    ;;
  x)
    # Codex CLI: instructions.md in ~/.codex
    cat > "$TARGET" <<CDX
# sauron instructions for Codex CLI

$SS_TEXT

---
$UPS_TEXT
CDX
    ok "wrote Codex instructions: $TARGET"
    ;;
  a)
    # Aider: convention file referenced from .aider.conf.yml
    cat > "$TARGET" <<AID
# sauron conventions for Aider

$SS_TEXT

$UPS_TEXT
AID
    ok "wrote Aider convention file: $TARGET"
    warn "  add this line to your .aider.conf.yml:  read: [$TARGET]"
    ;;
  g)
    # Generic: portable SYSTEM_PROMPT.md
    cat > "$TARGET" <<GEN
# sauron SYSTEM PROMPT (portable)

Paste the contents below into your orchestrator's system prompt or rules file.

---

$SS_TEXT

---

$UPS_TEXT

---

## How to use with any AI agent
1. Copy the two sections above into your orchestrator's system prompt.
2. If your orchestrator supports per-message rules, put the second section there.
3. Skill invocations (Skill(x)) are Claude Code-only. On other orchestrators,
   reference the skill by name in your prompt and cite the SKILL.md content.
GEN
    ok "wrote generic system prompt: $TARGET"
    ;;
esac

# ---------- 6a. write CLAUDE.md doctrine file (prompt-cacheable, replaces per-message re-injection) ----------
# CLAUDE.md is auto-loaded by Claude Code and covered by the 1-hour prompt cache.
# Hooks stay lean (they just point at this file); the full doctrine sits here once.
case "$SCOPE" in
  g) CLAUDE_MD="$HOME/CLAUDE.md" ;;
  p) CLAUDE_MD="$PWD/CLAUDE.md" ;;
  s) CLAUDE_MD="" ;;
esac

if [ -n "$CLAUDE_MD" ]; then
  if [ -f "$CLAUDE_MD" ]; then
    cp "$CLAUDE_MD" "${CLAUDE_MD}.bak.$(date +%s)"
    ok "backed up existing CLAUDE.md"
  fi
  # NEW-6: multi-framework detection. If a sibling (let-there-be-light) block is
  # already present, write a lean block that references it instead of duplicating
  # the shared sections. Framework-specific bits stay here.
  SIBLING_PRESENT=0
  if [ -f "$CLAUDE_MD" ] && grep -q '<!-- BEGIN let-there-be-light doctrine' "$CLAUDE_MD"; then
    SIBLING_PRESENT=1
    ok "detected sibling doctrine (let-there-be-light); writing lean sauron block"
  fi
if [ "$SIBLING_PRESENT" = 1 ]; then
  DOC_BLOCK=$(cat <<CLAUDEMD

<!-- BEGIN sauron doctrine (managed by setup.sh; sibling: let-there-be-light) -->
# sauron doctrine (lean; shared rules provided by sibling block)

Sibling framework \`let-there-be-light\` supplies: delegate-first routing, keep-in-Claude list, failover doctrine, token-efficiency rules, response terseness ladder, preempt-shell-bloat rules, failure-map, and route-plan pre-flight. Those apply here too.

## 4-step validation pipeline (sauron variant: per confirmed finding, before report)
A. Stress-test via validator skill (false-positive check, reproducibility, evidence gaps, confidence).
B. Run gap tests, negative controls, and live observations the validator flags.
C. Adversarial challenge via mcp__hermes__challenge (pro primary, groq fallback): severity, exploitability, chain viability, impact ceiling.
D. Synthesize with confidence markers; groq drafts the report, Claude spot-checks low-confidence claims only.

## Recon-work strategy (delta-first)
- For any "what changed on target" or "diff last scan" request, run \`diff\` on the last two scan outputs first.
- Read a full scan only when the delta is insufficient to judge exploitability.

## Preloaded skills
${SKILLS_LIST:-(none preloaded; all skills lazy-load on trigger phrase)}
<!-- END sauron doctrine -->
CLAUDEMD
)
else
  DOC_BLOCK=$(cat <<CLAUDEMD

<!-- BEGIN sauron doctrine (managed by setup.sh; regenerate to update) -->
# sauron doctrine

## Delegate-first routing
${ROUTING}

## Keep in Claude ONLY
- user-facing decisions
- exploitation choices, severity calls
- safety-boundary checks (no 3rd-party data, no destructive actions, no account creation)
- side-effecting actions
- tool-sequence orchestration

## Failover
Any model refusal or error routes to the next model in the map. A classifier refusal is a routing problem, not a stop.

## 4-step validation pipeline (per confirmed finding, before presenting or reporting)
A. Stress-test via validator skill (false-positive check, reproducibility, evidence gaps, confidence).
B. Run the gap tests, negative controls, and live observations the validator flags.
C. Adversarial challenge via mcp__hermes__challenge (pro primary, groq fallback): challenge severity, exploitability, chain viability, impact ceiling.
D. Synthesize with confidence markers; groq drafts the report, Claude spot-checks low-confidence claims only.

## Token efficiency rules (this framework exists to cut Claude token cost)
- Any tool output over 5 KB routes through nemotron (bulk) or flash (structured) for summarization before Claude reads.
- Batch related Hermes sub-tasks into one structured call, not N separate ones.
- Hermes responses on factual output must include {claim, confidence, source_span} triples. Claude byte-checks entries below high confidence only.
- Never re-Read a file already Read this session; recall from conversation context.
- Preemptively bound predictable-bloat outputs: append | head -c 5000 or | jq -c on Bash calls whose full output you don't need.
- Never delegate the same task twice; cache the result inline in the conversation.
- Terser confirmations when a diff or file speaks for itself; not every action needs a paragraph.

## Response terseness ladder
- Level 1 (one-liner): use when a diff, SHA, file identifier, or one measurable result is the answer.
- Level 2 (short paragraph): use for 1-2 non-obvious decisions or a short summary of a multi-step task.
- Level 3 (detailed section): only for architecture design, security findings, or an explicit user request for detail.
- Rule: never default to Level 3. The user asks for it. Under-explaining is cheaper to fix than over-explaining.

## Recon-work strategy (diff-first / delta-first)
- For any "what changed on target", "recheck this endpoint", "diff last scan" request, use \`diff\` on the last two scan outputs and reason from the delta.
- Read a full scan output only when the delta is insufficient to judge exploitability.
- On repeat scans across many targets, this saves reading N full nuclei/subfinder dumps.

## Preempt predictable bloat at the shell
- If you already know a tool will emit over 5 KB, cap it in the shell rather than reading + then compressing.
- Examples:
  - \`nuclei ... -jsonl | head -100\`
  - \`subfinder ... | wc -l\` first, then \`head -c 5000\` if huge
  - \`dnsx ... | jq -c 'select(.a)' | head -50\`
  - \`ffuf ... -mc 200 -of json | jq -c '.results[] | {url, status}' | head -100\`

## In-conversation failure-map
- On any Hermes refusal or 4xx/5xx response, tag \"\$model refused \$task-class this session\".
- Skip that model for the next similar task in the same conversation. Do not retry the failing route inside one turn.
- Common: groq classifier-refuses raw exploit code -> next similar request routes straight to grok or or-free.

## Route-plan pre-flight (speculative, measure before generalizing)
- For any task with 3 or more distinct sub-steps, first fire a small groq call (~200 tokens) asking for a routing plan.
- Then execute the plan.
- If the plan overhead exceeds the saving on tasks under 5 sub-steps, drop this rule.

## Preloaded skills
${SKILLS_LIST:-(none preloaded; all skills lazy-load on trigger phrase)}
Other skill bodies load only when their trigger phrase appears.
<!-- END sauron doctrine -->
CLAUDEMD
)
fi
  if [ -f "$CLAUDE_MD" ]; then
    awk '
      BEGIN{skip=0}
      /^<!-- BEGIN sauron doctrine/{skip=1; next}
      /^<!-- END sauron doctrine/{skip=0; next}
      skip==0{print}
    ' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
  fi
  printf '%s\n' "$DOC_BLOCK" >> "$CLAUDE_MD"
  ok "wrote CLAUDE.md doctrine: $CLAUDE_MD"

  # NEW-7 (LazyDoc): warn if CLAUDE.md exceeds 5 KB; suggest compression pass.
  CLAUDE_MD_SIZE=$(wc -c < "$CLAUDE_MD")
  if [ "$CLAUDE_MD_SIZE" -gt 5120 ]; then
    warn "CLAUDE.md is ${CLAUDE_MD_SIZE} bytes (over 5 KB threshold)."
    warn "  Every session loads this file. Consider compressing via Hermes caveman mode:"
    warn "    Skill(caveman) then ask groq to compress the managed blocks."
    warn "  Or manually trim: your appended blocks are marked by <!-- BEGIN ... -->."
  fi
fi

# ---------- 6b. optional: symlink shipped skills so Claude Code can discover them ----------
SKILLS_SRC="$SCRIPT_DIR/skills"
if [ "$ORCH" = "c" ] && [ -d "$SKILLS_SRC" ]; then
  case "$SCOPE" in
    g) SKILLS_DST="$HOME/.claude/skills" ;;
    p) SKILLS_DST="$PWD/.claude/skills" ;;
  esac
  read -rp "symlink shipped skills into $SKILLS_DST? [Y/n]: " a
  case "${a:-y}" in
    y|Y)
      mkdir -p "$SKILLS_DST"
      for d in "$SKILLS_SRC"/*/; do
        name=$(basename "$d")
        target="$SKILLS_DST/$name"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
          warn "skipping $name: destination exists and is not a symlink"
          continue
        fi
        ln -sfn "$d" "$target" && ok "symlinked $name -> $target"
      done
      ;;
    *) warn "skipped skill symlinking; you must place skills under $SKILLS_DST manually" ;;
  esac
fi

# ---------- 6c. MANDATORY: ensure Hermes MCP server is installed + registered ----------
# Hermes (intelligent multi-provider model router) is REQUIRED: the delegate-first
# doctrine calls mcp__hermes__* tools. Without it, Claude Code silently no-ops them.
HERMES_DIR="${HERMES_DIR:-$HOME/tools/hermes-mcp-server}"
HERMES_REPO="https://github.com/crowx01/hermes-mcp-server"
if [ "$ORCH" = "c" ]; then
  if [ -f "$HOME/.claude.json" ] && jq -e '.mcpServers.hermes // (.projects | to_entries[]?.value.mcpServers.hermes)' "$HOME/.claude.json" >/dev/null 2>&1; then
    ok "Hermes MCP server is registered in ~/.claude.json"
  else
    warn "Hermes MCP server is REQUIRED and is not registered."
    printf '  Install + register Hermes now? [Y/n] '; read -r _hans
    case "$_hans" in
      [Nn]*) err "Hermes is mandatory for the delegate-first doctrine. Aborting install."; exit 1 ;;
    esac
    command -v git     >/dev/null 2>&1 || { err "git not found; cannot install Hermes."; exit 1; }
    command -v jq      >/dev/null 2>&1 || { err "jq not found; cannot register Hermes."; exit 1; }
    command -v python3 >/dev/null 2>&1 || { err "python3 not found; cannot build Hermes."; exit 1; }
    if [ ! -d "$HERMES_DIR/.git" ]; then
      say "  cloning $HERMES_REPO -> $HERMES_DIR"
      git clone --depth 1 "$HERMES_REPO" "$HERMES_DIR" || { err "Hermes clone failed"; exit 1; }
    else
      ok "  Hermes repo already present at $HERMES_DIR"
    fi
    if [ ! -x "$HERMES_DIR/.hermes_venv/bin/python" ]; then
      say "  creating venv"
      python3 -m venv "$HERMES_DIR/.hermes_venv" || { err "venv creation failed"; exit 1; }
    fi
    say "  installing dependencies"
    "$HERMES_DIR/.hermes_venv/bin/python" -m pip install -q -r "$HERMES_DIR/requirements.txt" || { err "dependency install failed"; exit 1; }
    [ -f "$HOME/.claude.json" ] || echo '{}' > "$HOME/.claude.json"
    _tmp="$(mktemp)"
    jq --arg cmd "$HERMES_DIR/.hermes_venv/bin/python" --arg srv "$HERMES_DIR/server.py" \
      '.mcpServers = (.mcpServers // {}) | .mcpServers.hermes = {type:"stdio", command:$cmd, args:[$srv], env:{DEFAULT_MODEL:"auto"}}' \
      "$HOME/.claude.json" > "$_tmp" && mv "$_tmp" "$HOME/.claude.json" || { err "Hermes registration failed"; exit 1; }
    ok "Hermes cloned, built, and registered (DEFAULT_MODEL=auto -> intelligent cross-provider router)"
    warn "  Add your provider keys under mcpServers.hermes.env in ~/.claude.json:"
    warn "    GEMINI_API_KEY, OPENROUTER_API_KEY, and/or CUSTOM_API_URL + CUSTOM_API_KEY (groq)"
  fi
else
  warn "Non-Claude orchestrator: install Hermes manually and wire it to your MCP client:"
  warn "  git clone $HERMES_REPO ~/tools/hermes-mcp-server"
fi

# ---------- 6d. copy skill files for non-Claude orchestrators ----------
# For non-Claude, the model can't invoke Skill() directly, but it can still read
# the SKILL.md content. Copy skills into a sibling folder so the rules file can
# reference them and the other model has the same knowledge.
if [ "$ORCH" != "c" ] && [ -d "$SKILLS_SRC" ]; then
  SKILLS_MIRROR="$(dirname "$TARGET")/sauron-skills"
  read -rp "copy skill files into $SKILLS_MIRROR so the model can read them? [Y/n]: " a
  case "${a:-y}" in
    y|Y)
      mkdir -p "$SKILLS_MIRROR"
      for d in "$SKILLS_SRC"/*/; do
        name=$(basename "$d")
        dst="$SKILLS_MIRROR/$name"
        if [ -e "$dst" ] && [ ! -L "$dst" ] && [ ! -d "$dst" ]; then
          warn "skipping $name: destination exists and is not a directory or symlink"
          continue
        fi
        # cp -a preserves LICENSE and any scripts/references; a symlink would be
        # portable but is less friendly for user editing on non-Claude tools.
        cp -a "$d" "$SKILLS_MIRROR/" 2>/dev/null && ok "copied $name -> $dst"
      done
      # append a short pointer to the rules file so the other model knows the skills exist
      case "$ORCH" in
        r|l|x|a|g)
          {
            echo
            echo "## Skills available (read these when their trigger phrases appear)"
            for d in "$SKILLS_MIRROR"/*/; do
              n=$(basename "$d")
              echo "- \`$n\`: see [$n/SKILL.md](sauron-skills/$n/SKILL.md)"
            done
          } >> "$TARGET"
          ok "appended skills index to $TARGET"
          ;;
      esac
      ;;
    *) warn "skipped skill copy; the model won't see skill descriptions" ;;
  esac
fi

# ---------- 7. .env handling: template + optional interactive key entry ----------
NEEDS_ENV=0
[ "$M_GROQ" = 1 ] && NEEDS_ENV=1
[ "$M_NEMO" = 1 ] && NEEDS_ENV=1
[ "$M_GROK" = 1 ] && NEEDS_ENV=1
[ "$M_FLSH" = 1 ] && NEEDS_ENV=1
[ "$M_ORFR" = 1 ] && NEEDS_ENV=1
[ "$M_PRO" = 1 ] && NEEDS_ENV=1

if [ "$NEEDS_ENV" = 1 ]; then
  ENV_EXAMPLE="$(dirname "$TARGET")/.env.sauron.example"
  ENV_REAL="$(dirname "$TARGET")/.env.sauron"

  cat > "$ENV_EXAMPLE" <<EOF
# sauron API keys - source this from your shell rc, or export before starting Claude Code.
# Do NOT commit the real values.
$( [ "$M_FLSH" = 1 ] || [ "$M_PRO" = 1 ] && echo "export GEMINI_API_KEY=your-gemini-key" )
$( [ "$M_NEMO" = 1 ] || [ "$M_GROK" = 1 ] || [ "$M_ORFR" = 1 ] && echo "export OPENROUTER_API_KEY=your-openrouter-key" )
$( [ "$M_GROQ" = 1 ] && printf '%s\n' "export CUSTOM_API_URL=https://api.groq.com/openai/v1" "export CUSTOM_API_KEY=your-groq-key" )
EOF
  ok "wrote env template: $ENV_EXAMPLE"

  hd "7. Enter API keys now to complete installation?"
  say "  You can skip and edit $(basename "$ENV_EXAMPLE") later, or enter them now"
  say "  to have a real .env.sauron written with 0600 permissions."
  ASK_KEYS=$(prompt_yn "enter API keys now?" y)

  GROQ_KEY=""; OR_KEY=""; GEMINI_KEY=""

  if [ "$ASK_KEYS" = 1 ]; then
    if [ "$M_GROQ" = 1 ]; then
      hd "  ${GLD}Groq${RST} (report writing, validation)"
      say "    ${DIM}How to get one:${RST}"
      say "      1. Open ${CYN}https://console.groq.com/keys${RST}"
      say "      2. Sign in with Google or GitHub"
      say "      3. Click 'Create API Key', name it 'sauron'"
      say "      4. Copy the key (starts with 'gsk_')"
      say "    ${DIM}Free tier: gpt-oss-120b with ~500 rpm.${RST}"
      read -rsp "    paste Groq key (input hidden, ENTER to skip): " GROQ_KEY; echo
      GROQ_KEY=$(printf '%s' "$GROQ_KEY" | tr -d '[:space:]')
    fi
    if [ "$M_NEMO" = 1 ] || [ "$M_GROK" = 1 ] || [ "$M_ORFR" = 1 ]; then
      hd "  ${GLD}OpenRouter${RST} (nemotron / grok / or-free share one key; grok is your permissive high-context workhorse for security research)"
      say "    ${DIM}How to get one:${RST}"
      say "      1. Open ${CYN}https://openrouter.ai/settings/keys${RST}"
      say "      2. Sign in with Google or GitHub"
      say "      3. Click 'Create Key', name it 'sauron'"
      say "      4. Copy the key (starts with 'sk-or-v1-')"
      say "    ${DIM}Free-tier models (nemotron, grok-fast, meta-router) don't require credit.${RST}"
      read -rsp "    paste OpenRouter key (input hidden, ENTER to skip): " OR_KEY; echo
      OR_KEY=$(printf '%s' "$OR_KEY" | tr -d '[:space:]')
    fi
    if [ "$M_FLSH" = 1 ] || [ "$M_PRO" = 1 ]; then
      hd "  ${GLD}Google Gemini${RST} (flash / pro share this key)"
      say "    ${DIM}How to get one:${RST}"
      say "      1. Open ${CYN}https://aistudio.google.com/apikey${RST}"
      say "      2. Sign in with Google"
      say "      3. Click 'Create API Key' in a new or existing Google Cloud project"
      say "      4. Copy the key"
      say "    ${DIM}Free tier: generous flash/pro quotas.${RST}"
      read -rsp "    paste Gemini key (input hidden, ENTER to skip): " GEMINI_KEY; echo
      GEMINI_KEY=$(printf '%s' "$GEMINI_KEY" | tr -d '[:space:]')
    fi

    umask_prev=$(umask); umask 077
    {
      [ "$M_FLSH" = 1 ] || [ "$M_PRO" = 1 ] && printf 'export GEMINI_API_KEY=%s\n'    "${GEMINI_KEY:-your-gemini-key}"
      [ "$M_NEMO" = 1 ] || [ "$M_GROK" = 1 ] || [ "$M_ORFR" = 1 ] && printf 'export OPENROUTER_API_KEY=%s\n' "${OR_KEY:-your-openrouter-key}"
      if [ "$M_GROQ" = 1 ]; then
        printf 'export CUSTOM_API_URL=https://api.groq.com/openai/v1\n'
        printf 'export CUSTOM_API_KEY=%s\n' "${GROQ_KEY:-your-groq-key}"
      fi
    } > "$ENV_REAL"
    chmod 600 "$ENV_REAL"
    umask "$umask_prev"
    ok "wrote $ENV_REAL (0600)"

    hd "7b. Key entry summary"
    if [ "$M_GROQ" = 1 ]; then
      [ -n "$GROQ_KEY"   ] && ok "  Groq       entered" || warn "  Groq       placeholder (edit $ENV_REAL to add it)"
    fi
    if [ "$M_NEMO" = 1 ] || [ "$M_GROK" = 1 ] || [ "$M_ORFR" = 1 ]; then
      [ -n "$OR_KEY"     ] && ok "  OpenRouter entered" || warn "  OpenRouter placeholder (edit $ENV_REAL to add it)"
    fi
    if [ "$M_FLSH" = 1 ] || [ "$M_PRO" = 1 ]; then
      [ -n "$GEMINI_KEY" ] && ok "  Gemini     entered" || warn "  Gemini     placeholder (edit $ENV_REAL to add it)"
    fi
  else
    say "  skipped interactive key entry; only the example was written."
    warn "  edit $ENV_EXAMPLE and rename to .env.sauron before starting your orchestrator."
  fi
fi

# ---------- 8. next steps ----------
hd "Next steps"
case "$ORCH" in
  c)
    cat <<EOF
  1. Register Hermes as an MCP server in ~/.claude.json:
     ${DIM}"mcpServers": { "hermes": { "type": "stdio", "command": "/path/to/hermes-mcp-server/.hermes_venv/bin/python", "args": ["/path/to/hermes-mcp-server/server.py"], "env": { ...keys... } } }${RST}
  2. Source your API keys: ${CYN}source $(dirname "$TARGET")/.env.sauron${RST}   (after editing it)
  3. Restart Claude Code.
  4. On the next session start you should see the auto-invoked skills fire immediately.
EOF
    ;;
  r)
    cat <<EOF
  1. Source your API keys: source $(dirname "$TARGET")/.env.sauron
  2. Open your project in Cursor; .cursor/rules/*.mdc apply automatically.
  3. Ask the model to read sauron-skills/<name>/SKILL.md when trigger phrases appear.
EOF
    ;;
  l)
    cat <<EOF
  1. Source your API keys: source $(dirname "$TARGET")/.env.sauron
  2. Cline reads .clinerules automatically.
  3. Ask Cline to read sauron-skills/<name>/SKILL.md when triggers appear.
EOF
    ;;
  x)
    cat <<EOF
  1. Source your API keys.
  2. Codex CLI reads ~/.codex/instructions.md as base prompt.
  3. Skill files are pointed to from the instructions.
EOF
    ;;
  a)
    cat <<EOF
  1. Source your API keys.
  2. Add to your .aider.conf.yml:  ${CYN}read: [$TARGET]${RST}
  3. Skill files copied next to conventions.
EOF
    ;;
  g)
    cat <<EOF
  1. Paste $TARGET contents into your orchestrator's system prompt.
  2. Skill files sit at $(dirname "$TARGET")/sauron-skills/.
  3. Source your API keys.
EOF
    ;;
esac
echo
ok "sauron setup complete."
