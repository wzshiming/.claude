# AGENTS.md

Personal agents repository — agent definitions plus the scripts they run, no application code.

This file is named `AGENTS.md`, not `CLAUDE.md`, on purpose: the repository is checked out as `~/.claude`, where a root `CLAUDE.md` would load into every session of every project.

## Structure

Only `.github/`, `agents/`, `scripts/`, `tests/`, the dotfiles `.gitignore` lists, root Markdown docs, `LICENSE`, and `Makefile` are tracked; everything else at the root is Claude Code's local runtime state (settings, sessions, memory, the agents' ledger directory) excluded by the `.gitignore` whitelist.

### Scripts

- Each script lives in `scripts/<name>.sh` as POSIX sh (`#!/bin/sh`, clean under `shellcheck -s sh`), called as `~/.claude/scripts/<name>.sh [-C <repo-path>] <args>`; the lock block `take_lock` is identical in `scripts/worktree-add.sh` and `scripts/worktree-remove.sh` and is edited in both together.
- A script never prompts, reads no environment variable as configuration, and never forces; an unmet precondition makes it refuse and say why.
- Exit codes: `0` done, `1` refused or failed, `2` usage error; a script's `--help` may define more (`ci-wait.sh`: `3` still pending at the deadline); results print as `key=value` lines, a listing (`worktree-status.sh`) as one line per item, a watcher as one progress line per poll plus the final table; `--help` prints one paragraph.
- Tests live in `tests/<name>.bats` (bats-core); reusable fake commands live in `tests/mock/<cmd>`, clean under `shellcheck -s sh`, never as stubs written inside a single `.bats` file.

### Agents

- Each agent lives in `agents/<name>.md` with YAML frontmatter: `name` (lowercase, equal to the file name), `description`, `model` (one alias), `tools` (an allowlist, so an agent holds nothing its role does not use), and `color` (one each); a main agent's `tools` lists its dispatchable subagents as `Agent(<name>, …)`, a subagent that dispatches lists plain `Agent`.
- Main agents — planner, orchestrator, challenger — are started with `claude --agent <name>`; planner and orchestrator need `AskUserQuestion`, which no subagent has, so they are never dispatched. A transition between main agents is a new session the finishing agent recommends, naming the plan or ledger file it hands over; the target agent's body supplies the method.
- Nesting stays within the harness's three subagent layers: orchestrator → challenger → reviewer → executor is the deepest chain.
- Challenger and reviewer share one verbatim `## Constraints` block and the quoted fit question; orchestrator and that block share the executor-dispatch sentence; scout, executor, and coder share the auto-approval bullet; planner, orchestrator, and challenger share the Language rule, the Parallel dispatch rule, and the Memory rule — there is no include mechanism, so edit every copy together (`tests/drift.bats`).

## Checks

- `make check` — Prettier format check + markdownlint + shellcheck + bats, the full suite.
- `make format-check` — Prettier check on Markdown.
- `make lint` — markdownlint on Markdown + `shellcheck -s sh` on `scripts/*.sh` and `tests/mock/*` + `shellcheck -s bash` on `tests/helpers.bash`; `.bats` files are not shellchecked.
- `make test` — bats-core on `tests/*.bats`.
- `make format` — Prettier rewrites Markdown.
- These targets, or the commands they run on specific files, may run locally without asking.
- CI (`.github/workflows/ci.yml`) runs `make check` on `ubuntu-latest` and `macos-latest` for pushes to `master` and all PRs.

## Conventions

- Agents orchestrate, executor executes: a body holds its flow plus only its role's knowledge; the git/gh workflow lives only in executor's Rules, each fixed multi-command flow is a script in `scripts/`, and the dispatchers — orchestrator, reviewer, and challenger — name a git/gh step by its intent alone, the exceptions being the coder's own fixed commands: the worktree scripts that cut and release its worktree, `git add`/`git commit`, `git restore`/`rm`, and the `git worktree remove` undoing an accidental attach (its Git writes constraint, Worktree and Release steps); no body restates the harness system prompt, though a main agent's body replaces it entirely and a subagent never receives it, so a body carries every rule its role depends on.
- Agent bodies open with one sentence in normal case, `You are the <role>: <mission>.` — no shouted words.
- Agent body sections are H2 only, one per name, in this order and only when needed: Input, Constraints, Approach (a subagent's checklist) or Workflow (the orchestrator's and planner's phase loop), Rules, Output Format.
- List items are fragments or single sentences without a terminal period — split an item rather than write two sentences in it; only Workflow phase items are paragraphs with a bold `**Phase**:` label and full punctuation, every other label is plain `Label:`.
- Emphasis: `_agent_` italics for agent names, written as the frontmatter `name`, bold only for Workflow phase names — their labels and references back to them — and a body's key-fact line (`**Ledger**`, `**Current plan**`), backticks for paths, commands, tools, and model aliases; a list's lead-in sentence ends with a colon.
- Descriptions: one double-quoted line; at most 35 words before `Brief:`, shorter preferred — one outcome clause (what it does, not its steps), then `Use when:` with up to three comma- or semicolon-separated triggers specific to the task; no model names; a dispatchable agent's description ends with its `Brief:` clause and names no other agent, a main agent's may name the agents that feed it (`tests/agents.bats`).
- Shell: auto-approvable and self-contained; a fixed flow is one script call, approvable whole; no `export …;` preamble or `VAR=… cmd` prefix; guards are flags, not environment; `gh` output piped; every run in the foreground to its exit, one the harness moves to the background at its timeout waited on rather than started again (executor's Constraints and Rules, coder's Terminal constraint, the auto-approval bullet shared by scout, executor, and coder).
- Testing: the full suite runs on CI as the merge gate and local runs stay targeted — the baseline is the start commit's CI result, taken once per task (orchestrator's Intake), else one local run, and a local full run comes only before a landing to no PR or when CI is unreachable (executor's CI and Landing rules, `scripts/ci-wait.sh`).
- Execution: only scout (side-effect-free reads), executor (git/gh flows and dispatched checks), and coder (its own worktree's tests, builds, checks, and fixed git steps) have `Bash`; orchestrator, reviewer, and challenger dispatch executor by its `Brief:`, one dispatch per step; destructive commands only when named (executor's Constraints and Rules, coder's Constraints, the shared executor-dispatch sentence).
- Implementation: the orchestrator copies each module entry into the ledger as its stage's contract and runs the stage by one coder writing tests and implementation together (its Intake and Execute); a coder creates and releases its own worktree through the scripts, never the harness's `isolation: worktree`, so its stage exists only as the branch it reports (coder's Worktree and Release steps); executor lands a wave's branches in dependency order and cleans up by branch, combining only by rebase and fast-forward, never a merge commit (its Landing rule, `scripts/worktree-*.sh`).
- Review: the review requirement is the user's choice among review gates as the orchestrator schedules them (the default), one review gate before landing only, or none; reviewer runs at the gates only and challenger only when the user asks or a gate fails three reviewer rounds (orchestrator's Intake and Verify, planner's Alignment).
- Design: the planner designs from the whole by criteria that live only in its Modules rule; the orchestrator decomposes the design; coder implements the contract, reporting rather than writing a patch or restructuring the plan did not foresee; reviewer and challenger ask the fit question against the plan's decisions and criteria (their Approach).
- Planning: the planner's Outline, approved by the user, is the only plan format, each module entry carrying its acceptance criteria and becoming the ledger's stage contract verbatim (planner's Output Format, orchestrator's Intake).
- Files: plans and ledgers live in `~/.claude/ledger/<repo>/` as `plan-<slug>.md` and `task-<slug>.md`, the only files planner and orchestrator read or write with their own tools (planner's **Current plan**, orchestrator's **Ledger**).
- Dispatch interface across agents: the description's `Brief:` clause is the single home of what a dispatch must carry, because a dispatcher sees only a target's description; `## Input` restates it with semantics and adds nothing; a dispatcher's brief adds only what the clause cannot know and never describes the target's method; no body describes another agent's mechanics (orchestrator's `Stage dispatches:` rule).
- Dispatch policy across agents: subagent dispatches needing none of one another's results or side effects form one batch issued in one message of `Agent` calls; a dispatch issued after another has returned runs alone; each body names its batches (the shared `Parallel dispatch:` rule).
- Dispatch models across agents: a dispatch runs on the alias its dispatcher names via the `Agent` call's `model` parameter, else on the target's `model`, and only the orchestrator, for every coder dispatch by the stage's difficulty, and challenger, for its three reviewer dispatches, name one; on a model family change, the aliases in those two bodies change together with the frontmatter `model` fields (orchestrator's `Coder model:` rule, challenger's Cross-examination step).
- Language: planner, orchestrator, and challenger share one `Language:` rule — replies and questions (options included) in the user's language, read from the user's own messages and never from a plan, a ledger, or a brief, naming anything referred to (stages, modules, waves, review gates, decisions, findings) by what it is, never by the plan's, the ledger's, or their own numbers or labels; nothing else is bound to it; commits, issues, and PR text keep the project's language (coder's Commit step, executor's PR and Issue rules).
- Memory: planner, orchestrator, and challenger share one `Memory:` rule — a memory entry is one line of at most about 300 characters stating one reusable rule, newest first within the 200 lines the harness loads, outdated entries deleted, evidence and narrative in the ledger directory (their Rules).
- Built-in models: where a role matches one of Claude Code's own agents its body follows that agent's definition — scout the Explore agent's read-only prohibitions, tool order, parallel calls, and `quick`/`medium`/`very thorough` vocabulary, planner the Plan agent's critical-files list, coder and the reviewing agents the general-purpose agent's file-creation and no-re-delegation rules (scout's Constraints and Rules, planner's Output Format, coder's Files rule, the shared `## Constraints` block).
- Reports: scout, executor, coder, and reviewer cap a report at 5000 characters unless the brief sets another bound (their Output Formats).
