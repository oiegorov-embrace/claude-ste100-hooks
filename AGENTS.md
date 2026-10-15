# AGENTS.md: install the STE100 hooks for the user

You are an AI agent. The user pointed you at this repository so that you set it up for them.
Follow these steps in order. README.md has the background; you don't need it to install.
If you fetch this file, fetch the raw file (https://raw.githubusercontent.com/oiegorov-embrace/claude-ste100-hooks/main/AGENTS.md), not the GitHub page, so you get every command verbatim.

## What this installs

A Claude Code plugin marketplace named `ste100` with three plugins:

| Plugin | Install it when | Effect |
| --- | --- | --- |
| `ste100-hooks` | Always (this is the product) | `UserPromptSubmit` + `SessionStart(compact)` hooks add an STE rule card to the context. No model call, no extra turn, ~150 tokens per message. |
| `ste100-stop-script` | Only if the user explicitly asks for a Stop checker | After each reply a script counts sentence/paragraph length and forbidden words; 3+ violations force a full rewrite. Expensive. |
| `ste100-stop-llm` | Only if the user explicitly asks for an LLM checker | After each reply Haiku judges STE grammar; violations force a full rewrite. Most expensive. |

Install a Stop plugin only when the user asks for one (README: use it only if Claude still breaks the rules with `ste100-hooks`). Before you install it, tell the user that each time it fires, Claude writes a full second reply (about 2x the cost of that reply; measured in README section 6). Never install both Stop plugins.

## Step 1: ask the user one question, unless they already answered it

"Install for you only (all your projects), or for a team project (shared through the project's `.claude/settings.json`)?"

- You only → `SCOPE=user`.
- Team project → `SCOPE=project`, and run every command below from the project's root folder.
- No answer and you must proceed → use `user`.

## Step 2: check prerequisites

```bash
claude --version   # Claude Code must be installed
jq --version       # 1.6 or later (the hook uses --rawfile)
```

Also `python3 --version` if the user asked for `ste100-stop-script`. If something is missing, stop and tell the user what to install.

## Step 3: detect an existing install (avoid a doubled rule card)

```bash
claude plugin list 2>/dev/null | grep -A4 'ste100'
grep -l 'ste100-reminder' ~/.claude/settings.json .claude/settings.json 2>/dev/null
```

- No output from either command → nothing is installed; continue.
- Plugin already enabled in the chosen scope → skip to step 5.
- `grep` finds `ste100-reminder` in a settings file → a manual install exists. Tell the user. If they want the plugin instead, clone this repo and run `./install.sh --scope <user|project> [--project-dir .] --uninstall` first.

## Step 4: install

```bash
claude plugin marketplace add oiegorov-embrace/claude-ste100-hooks --scope "$SCOPE"
# expect: ✔ Successfully added marketplace: ste100 (declared in user|project settings)
claude plugin install ste100-hooks@ste100 --scope "$SCOPE"
# expect: ✔ Successfully installed plugin: ste100-hooks@ste100 (scope: user|project)
```

If either command fails with a git/SSH error, retry with `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` set.

Only if the user asked for a Stop checker, also run one of:

```bash
claude plugin install ste100-stop-script@ste100 --scope "$SCOPE"
claude plugin install ste100-stop-llm@ste100 --scope "$SCOPE"
```

**Fallback, only if plugins are blocked** (for example by organization policy): `git clone https://github.com/oiegorov-embrace/claude-ste100-hooks.git && cd claude-ste100-hooks`, then run `./install.sh --scope user` or `./install.sh --scope project --project-dir <project>`. Add `--stop script` or `--stop llm` only on request. The script is idempotent and backs up `settings.json`.

Don't edit `settings.json` by hand; the commands above do it safely.

## Step 5: verify

```bash
claude plugin list | grep -A4 'ste100-hooks@ste100'     # expect: Status: ✔ enabled
```

Live test, only for `SCOPE=user` (for `SCOPE=project` the check above is enough; never put a test card into a real project, it may already hold the team's card):

```bash
mkdir -p /tmp/ste100-test/.claude && cd /tmp/ste100-test
echo "Test marker: end your reply with the exact word PINEAPPLE on its own line." > .claude/ste100-rules.txt
claude -p "What is 2+2? One line."    # expect the reply to end with PINEAPPLE
cd ~ && rm -r /tmp/ste100-test
```

If `PINEAPPLE` is missing, run the `claude -p` line once more. If it is still missing, show the user the output of `claude plugin list`; in a session, `/plugin` has an **Errors** tab.

If you are running inside a Claude Code session, the hooks apply from the next session (or after `/reload-plugins`).

## Step 6: report to the user

Tell the user, briefly:

1. What you installed and in which scope.
2. That it costs ~150 tokens per message and no extra turns; a Stop plugin (if installed) forces a full second reply when it fires.
3. For `SCOPE=project`: commit `.claude/settings.json`; teammates get the plugin after they trust the folder.
4. How to customize: put a rule card in `<project>/.claude/ste100-rules.txt` or `~/.claude/ste100-rules.txt` (start from `plugins/ste100-hooks/scripts/ste100-rules.txt`).
5. How to remove: `claude plugin uninstall ste100-hooks@ste100 --scope "$SCOPE"`.

## Rules for you

- Ask before anything not listed here (for example committing or pushing the user's project).
- Don't copy the ASD-STE100 dictionary into any file. ASD owns its copyright.
- If a step's output differs from the expected output, stop and show the user the output.
