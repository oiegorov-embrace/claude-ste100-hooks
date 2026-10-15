#!/bin/bash
# Proves that install.sh merges into existing settings and never overwrites them.
# Uses a throwaway HOME (mktemp) with a rich settings.json and CLAUDE.md, both symlinked into a
# "dotfiles" folder with mode 644. Checks install, a second install, and --uninstall.
# Usage: tests/merge-safety.sh [install.sh options]
#   default options: --scope user --stop llm   (the self-learning repo's installer needs none)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; FX="$REPO/tests/fixture"
ARGS=("$@")
if [ ${#ARGS[@]} -eq 0 ] && grep -q -- '--scope' "$REPO/install.sh"; then ARGS=(--scope user --stop llm); fi

H=$(mktemp -d); D=$H/dotfiles; mkdir -p "$D" "$H/.claude"
cp "$FX/settings.json" "$D/settings.json"; cp "$FX/claude-md.txt" "$D/CLAUDE.md"; chmod 644 "$D"/*
ln -s "$D/settings.json" "$H/.claude/settings.json"; ln -s "$D/CLAUDE.md" "$H/.claude/CLAUDE.md"
printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$H/.gitconfig"

# The hook entries the installers add; everything else must stay exactly as it was.
own='def own: ((.command // "") | test("/ste100-(reminder\\.sh|stop-check\\.py)\"?$|skill-learning-reminder\\.sh|skill-review/stop-hook\\.sh"))
       or ((.prompt // "") | startswith("You check if a reply follows ASD-STE100"));
     .hooks |= (with_entries(.value |= (map(.hooks |= map(select(own|not))) | map(select(.hooks|length>0)))) | with_entries(select(.value|length>0)))'
mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
n() { jq '[.hooks[][].hooks[]] | length' "$1"; }
pass=0; fail=0
ok() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
run() { HOME=$H GIT_CONFIG_NOSYSTEM=1 "$REPO/install.sh" "$@" >/dev/null 2>"$H/err" || echo "installer error: $(cat "$H/err")"; }

run ${ARGS[@]+"${ARGS[@]}"}
ok "settings.json is still a symlink"     '[ -L "$H/.claude/settings.json" ]'
ok "CLAUDE.md is still a symlink"         '[ -L "$H/.claude/CLAUDE.md" ]'
ok "settings.json mode is still 644"      '[ "$(mode "$D/settings.json")" = 644 ]'
ok "all non-hook settings unchanged"      '[ "$(jq -S "del(.hooks)" "$D/settings.json")" = "$(jq -S "del(.hooks)" "$FX/settings.json")" ]'
ok "existing hooks unchanged, same order" '[ "$(jq -S "$own" "$D/settings.json")" = "$(jq -S . "$FX/settings.json")" ]'
ok "new hooks were added"                 '[ "$(n "$D/settings.json")" -gt "$(n "$FX/settings.json")" ]'
ok "CLAUDE.md original text kept"         'head -c "$(wc -c < "$FX/claude-md.txt")" "$D/CLAUDE.md" | cmp -s - "$FX/claude-md.txt"'
cp "$D/settings.json" "$H/after1.json"
run ${ARGS[@]+"${ARGS[@]}"}
ok "second install changes nothing"       'cmp -s "$D/settings.json" "$H/after1.json"'
run ${ARGS[@]+"${ARGS[@]}"} --uninstall
ok "uninstall restores settings"          '[ "$(jq -S . "$D/settings.json")" = "$(jq -S . "$FX/settings.json")" ]'
ok "uninstall restores CLAUDE.md"         '[ "$(cat "$D/CLAUDE.md")" = "$(cat "$FX/claude-md.txt")" ]'
ok "symlinks kept after uninstall"        '[ -L "$H/.claude/settings.json" ] && [ -L "$H/.claude/CLAUDE.md" ]'

echo "$pass passed, $fail failed (test home: $H)"
[ "$fail" = 0 ]
