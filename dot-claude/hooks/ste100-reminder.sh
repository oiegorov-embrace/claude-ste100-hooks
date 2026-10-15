#!/bin/bash
# UserPromptSubmit and SessionStart (matcher "compact") hook.
# Puts the STE100 rule card (ste100-rules.txt, next to this script) in front of Claude:
# - on each user message, so the rule is always the most recent instruction;
# - after compaction, so the rule survives when the summary drops the skill text.
# Costs no extra turn and no model call: it only adds text to the context.
set -euo pipefail

event=$(jq -r '.hook_event_name // "UserPromptSubmit"')
rules="$(dirname "$0")/ste100-rules.txt"
[ -r "$rules" ] || exit 0

jq -n --arg e "$event" --rawfile c "$rules" \
  '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
