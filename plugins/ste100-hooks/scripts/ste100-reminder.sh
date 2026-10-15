#!/bin/bash
# UserPromptSubmit and SessionStart (matcher "compact") hook.
# Puts the STE100 rule card in front of Claude:
# - on each user message, so the rule is always the most recent instruction;
# - after compaction, so the rule survives when the summary drops the skill text.
# Costs no extra turn and no model call: it only adds text to the context.
#
# Rule card lookup, first match wins:
#   1. $CLAUDE_PROJECT_DIR/.claude/ste100-rules.txt   (team override, committed in the project)
#   2. ~/.claude/ste100-rules.txt                     (personal override)
#   3. ste100-rules.txt next to this script           (default card)
set -euo pipefail

event=$(jq -r '.hook_event_name // "UserPromptSubmit"')

# Plugin copy only: step aside when install.sh registered the same hook in a settings file,
# so the rule card never comes twice.
here="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ "${here#"$CLAUDE_PLUGIN_ROOT"}" != "$here" ]; then
  grep -qs '/ste100-reminder\.sh' "$HOME/.claude/settings.json" \
    "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" && exit 0
fi
rules=""
for f in "${CLAUDE_PROJECT_DIR:-}/.claude/ste100-rules.txt" "$HOME/.claude/ste100-rules.txt" "$(dirname "$0")/ste100-rules.txt"; do
  if [ -r "$f" ]; then rules="$f"; break; fi
done
[ -n "$rules" ] || exit 0

jq -n --arg e "$event" --rawfile c "$rules" \
  '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
