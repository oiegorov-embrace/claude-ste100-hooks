#!/bin/bash
# Manual installer for the STE100 hooks, for setups that can't use Claude Code plugins.
# Prefer the plugin install in README.md / AGENTS.md. Safe to run again: it replaces its own
# hook entries instead of adding duplicates, and it backs up settings.json before each change.
#
# Usage:
#   ./install.sh --scope user                          # ~/.claude, all your projects
#   ./install.sh --scope project --project-dir DIR     # DIR/.claude, the whole team (commit it)
#   options:  --stop none|script|llm   (default none; script/llm are expensive, see README)
#             --uninstall              remove the hook entries and scripts this installer added
set -euo pipefail

SCOPE="" PROJECT_DIR="" STOP="none" UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --stop) STOP="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$SCOPE" in
  user) BASE="$HOME/.claude"; HOOKDIR_REF='~/.claude/hooks' ;;
  project)
    [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || { echo "--scope project needs an existing --project-dir" >&2; exit 2; }
    BASE="$(cd "$PROJECT_DIR" && pwd)/.claude"; HOOKDIR_REF='"$CLAUDE_PROJECT_DIR"/.claude/hooks' ;;
  *) echo "Set --scope user or --scope project" >&2; exit 2 ;;
esac
case "$STOP" in none|script|llm) ;; *) echo "--stop must be none, script or llm" >&2; exit 2 ;; esac
command -v jq >/dev/null || { echo "jq is required (1.6 or later)" >&2; exit 1; }
[ "$STOP" = script ] && { command -v python3 >/dev/null || { echo "python3 is required for --stop script" >&2; exit 1; }; }

REPO="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$BASE/settings.json"
mkdir -p "$BASE/hooks"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" || { echo "$SETTINGS is not valid JSON; fix it first" >&2; exit 1; }
cp "$SETTINGS" "$SETTINGS.bak-ste100-$(date +%Y%m%d-%H%M%S)"

# Write settings.json through a temp file; stop with an error if jq fails or the result is invalid.
apply() {
  if jq "$@" "$SETTINGS" > "$SETTINGS.tmp" && jq empty "$SETTINGS.tmp"; then
    mv "$SETTINGS.tmp" "$SETTINGS"
  else
    rm -f "$SETTINGS.tmp"; echo "Could not update $SETTINGS; it is unchanged." >&2; exit 1
  fi
}

# Remove every hook entry this installer owns (its commands contain "ste100-"), and empty leftovers.
strip='def own: (.command // "") | test("ste100-");
  .hooks = ((.hooks // {})
    | with_entries(.value |= (map(.hooks |= map(select((own | not) and ((.prompt // "") | test("ASD-STE100") | not))))
                              | map(select(.hooks | length > 0))))
    | with_entries(select(.value | length > 0)))
  | if .hooks == {} then del(.hooks) else . end'

if [ "$UNINSTALL" = 1 ]; then
  apply "$strip"
  rm -f "$BASE/hooks/ste100-reminder.sh" "$BASE/hooks/ste100-rules.txt" "$BASE/hooks/ste100-stop-check.py" "$BASE/hooks/ste100-forbidden-words.txt"
  echo "Removed STE100 hooks from $SETTINGS (backup next to it)."
  exit 0
fi

cp "$REPO/plugins/ste100-hooks/scripts/ste100-reminder.sh" "$REPO/plugins/ste100-hooks/scripts/ste100-rules.txt" "$BASE/hooks/"
chmod +x "$BASE/hooks/ste100-reminder.sh"
reminder="$HOOKDIR_REF/ste100-reminder.sh"
add=$(jq -n --arg c "$reminder" '{UserPromptSubmit: [{hooks: [{type: "command", command: $c}]}],
  SessionStart: [{matcher: "compact", hooks: [{type: "command", command: $c}]}]}')

if [ "$STOP" = script ]; then
  cp "$REPO/plugins/ste100-stop-script/scripts/ste100-stop-check.py" "$REPO/plugins/ste100-stop-script/scripts/ste100-forbidden-words.txt" "$BASE/hooks/"
  chmod +x "$BASE/hooks/ste100-stop-check.py"
  add=$(jq --arg c "$HOOKDIR_REF/ste100-stop-check.py" '. + {Stop: [{hooks: [{type: "command", command: $c}]}]}' <<<"$add")
elif [ "$STOP" = llm ]; then
  add=$(jq --slurpfile l "$REPO/plugins/ste100-stop-llm/hooks/hooks.json" '. + {Stop: $l[0].hooks.Stop}' <<<"$add")
fi

apply --argjson add "$add" "$strip"' | .hooks = (reduce ($add | to_entries[]) as $e ((.hooks // {}); .[$e.key] = ((.[$e.key] // []) + $e.value)))'

echo "Installed STE100 hooks in $SETTINGS (scope: $SCOPE, stop checker: $STOP)."
echo "Test: echo '{\"hook_event_name\":\"UserPromptSubmit\"}' | $BASE/hooks/ste100-reminder.sh | jq -r .hookSpecificOutput.additionalContext"
