# .claude

My personal .claude

## Agents and skills

| Role           | Runs as                | Role                                                         |
| -------------- | ---------------------- | ------------------------------------------------------------ |
| `planner`      | skill `/planner`       | Researches, clarifies, and writes the plan; never implements |
| `orchestrator` | skill `/orchestrator`  | Drives a plan or a long task to its landing through the rest |
| `challenger`   | main agent or subagent | Cross-examines a plan or a change through three reviewers    |
| `scout`        | subagent               | Read-only codebase exploration                               |
| `coder`        | subagent               | Implements one stage test-first in its own worktree          |
| `reviewer`     | subagent               | Verifies a target against its acceptance criteria            |
| `executor`     | subagent               | Runs commands and the git/gh flows in `scripts/`             |

Start a role with `/planner` or `/orchestrator` in any Claude Code session, the desktop app included, and `challenger` with `claude --agent challenger` or by asking a session to dispatch it; the usual chain is `/planner`, then `/orchestrator` in a new session — the plan and the task ledger are files under `~/.claude/ledger/<repo>/`, so nothing depends on the earlier session.

## Claude Code settings

The agents assume these user settings; `settings.json` is outside this repo's tracked whitelist, so they are recorded here:

```json
{
  "permissions": {
    "allow": [
      "Read(~/.claude/ledger/**)",
      "Edit(~/.claude/ledger/**)",
      "Bash(~/.claude/scripts/worktree-add.sh:*)",
      "Bash(~/.claude/scripts/worktree-remove.sh:*)",
      "Bash(~/.claude/scripts/worktree-status.sh:*)",
      "Bash(~/.claude/scripts/ci-wait.sh:*)"
    ]
  }
}
```

- The ledger rules let `planner` and `orchestrator` keep their plan and ledger files outside the project without a prompt per write
- The script rules approve each fixed git/gh flow whole
- `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` stays at its default of three or more: the `/orchestrator` session → `challenger` → `reviewer` → `executor` is the deepest dispatch chain, and every command of `reviewer` and `challenger` routes through `executor`
- The `haiku`, `sonnet`, `opus`, and `fable` aliases must all be available: `orchestrator` picks the `coder` model per stage and `challenger` pins one per review
