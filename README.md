# agent-supervisor

`ai-agents` runs a team of Claude Code agents on one task, one agent per GitHub repository, side by side in tmux. You pick what to start from a menu, and it watches the agents for you: who works, who waits for you, what it costs, and it restarts an agent that crashes.

## What you get

- **A menu, no flags to remember.** Run `ai-agents` and answer one question at a time.
- **Any GitHub organisation.** Pick your account or an organisation; every repository is offered. Repositories you don't have locally are cloned when you first use them.
- **One task = one branch everywhere.** Each agent gets its own git worktree, so your main checkouts stay untouched.
- **Agents talk to each other.** Each agent knows the others on its task and messages them when something they depend on changes.
- **A monitor.** What every agent is doing right now, grouped by task, with changed files, pull requests, tokens and cost.
- **Notifications.** A Mac notification names the task and agent when one needs you, may be stuck, or crashed.
- **Recovery.** A crashed agent restarts and continues its conversation (at most 3 times an hour). After a Mac restart, one menu item resumes every task.

## Install

Needs macOS and these tools, at least the version shown. Each minimum is the release that added the newest feature `ai-agents` uses.

| Tool | Minimum | Why that version | Tested with |
|---|---|---|---|
| [Claude Code](https://claude.com/claude-code) | 2.1.287 | `asyncRewake` hooks wake idle agents (also needs `--name` 2.1.76, `StopFailure` 2.1.78) | 2.1.330 |
| tmux | 3.2 | `new-session -e`; also the `prefix + a` popup | 3.8 |
| fzf | 0.71.0 | `--track --id-nth` keeps the cursor on the same row while lists refresh | 0.75.0 |
| GitHub CLI `gh`, logged in | 2.7.0 | `gh search issues --owner` for the issue picker | 2.96.0 |
| git | 2.22 | `git branch --show-current` | 2.50.1 |
| jq | 1.5 | `--slurpfile`, `@tsv`, regex functions | 1.8.2 |
| bash | 3.2 | the one macOS ships at `/bin/bash` | 3.2.57 |
| curl | 7.40 | `--unix-socket` for live refresh | 8.7.1 |

Also used, all part of macOS: `osascript` (notifications), `perl`, `md5`. Tested on macOS 26.7. iTerm2 and Docker are optional.

Claude Code 2.1.287 is a safe minimum, not an exact one: `asyncRewake` exists there, but its changelog doesn't say when it was added.

```sh
brew install tmux fzf jq gh
git clone https://github.com/juhasztibi/agent-supervisor ~/Projects/agent-supervisor
ln -s ~/Projects/agent-supervisor/ai-agents ~/.local/bin/ai-agents   # any folder on your PATH
ai-agents selftest                                                   # about 30 seconds, touches nothing of yours
```

Let the agents run the commands they use to work together, without asking you each time (`~/.claude/settings.json`, under `permissions.allow`):

```json
"Bash(ai-agents ls)", "Bash(ai-agents start *)", "Bash(ai-agents stop *)",
"Bash(ai-agents handoff *)", "Bash(ai-agents wait *)", "Bash(ai-agents inbox)",
"Bash(ai-agents ask *)", "Bash(ai-agents reply *)", "Bash(ai-agents send *)"
```

Optional tmux keys (add to `~/.tmux.conf`):

```tmux
bind a display-popup -E -w 90% -h 90% "AA_POPUP=1 AA_OPEN=here ~/.local/bin/ai-agents"   # prefix + a: the menu
bind O run-shell "~/.local/bin/ai-agents monitor-pane '#{pane_id}'"                       # prefix + O: monitor on the side
```

## Daily use

1. **Open the menu:** `ai-agents`, or `prefix + a` in tmux. Pick the organisation (the last one is on top, so Enter).
2. **Start work:** `1 Start new agents` → new task, or a task from a GitHub issue → tick the repositories → model and effort per agent → the goal. The agents open in a new window and start.
3. **Keep an eye on them:** `m` or `7 Monitor`. Tasks that need you are on top. Enter on an agent: open it, send it a message, change its model, stop it.
4. **Answer when asked:** a notification tells you which task and agent waits. `2 Running agents` opens it.
5. **Next morning:** `3 Resume agents` continues the conversations where they stopped.
6. **Done:** `5 Remove agents` stops them and deletes worktrees, panes and the task's Docker containers. Branches stay.

Keys in every screen: Enter chooses, Esc or `← Back` goes back, type to search. On the overview: `1`-`8` jump, `m` monitor, `o` switch organisation, `r` refresh, `q` quit.

## How agents work together

Agents talk only through `ai-agents`, so every message is stored, delivered and tracked. Run from an agent's session:

- `handoff <agent|all> "what changed"`: after committing; points the others at the commit and ends their waits.
- `wait <agent> "what I need"`: the Monitor shows "⧗ waiting for be" until the handoff arrives.
- `ask <agent> "question"`, `reply <id> "answer"`, `send <agent|all> "note"`, `inbox`. `agent@task` reaches an agent of another task.

Nothing is ever typed into an agent's pane: each pane runs Claude Code directly. Claude Code hooks add new messages to its context at its next step, and a turn that ends with messages waiting continues with them. An idle agent is woken by a background listener (an `asyncRewake` hook) with the messages themselves. A stopped agent gets its messages when it starts. Your own `ai-agents say` messages travel the same way. The watchdog tells you about messages it can't deliver, questions unanswered for 15 minutes and waits longer than 30 minutes (`AA_ANSWER_SEC`, `AA_WAIT_SEC`).

**Trust model.** All agents run as your user, so an agent with free shell access can do anything you can, including writing the message files or posing as you. The message system keeps honest agents and agents misled by text (an issue body, another agent's message) apart from your instructions: other agents' words always arrive quoted, and `say` refuses to run from an agent. The real boundary is Claude Code's permission settings, so don't give agents unrestricted shell access.

When an agent is about to edit a file that an agent of another task already changed in the same repo, the first edit is stopped and it is told to ask that agent (`ai-agents ask be@t1 "..."`) and agree who does it. Once they agree, the same edit goes through. The Monitor shows "⚠ overlap with <task>".

## Commands

The menu covers everything; these are for scripts and for the agents themselves.

```sh
ai-agents up <task> "goal" --only api,web     # new task with these agents
ai-agents start <task> api --model opus       # start or add an agent
ai-agents say <task> all "rebase on main"     # type a message into every running agent
ai-agents ls                                   # what runs where
ai-agents stop <task> web | resume <task> | down <task> --prune
ai-agents orgs | org <owner> | --org <owner> <command>
ai-agents help                                 # everything else
```

## Settings

Per organisation in `~/.config/ai-agents/orgs/<owner>/`: `repos` (the agents) and an optional `settings` file with tab-separated `worktrees <folder>`, `prefix <tmux prefix>` and `issues <owner/repo>`.

Environment variables you may want: `AA_OPEN` (window, tab, here, detached), `AA_LAYOUT` (own, split), `AA_REMOTE` (Remote Control on or off), `AA_NOTIFY`, `AA_AUTO_RESTART`, `AA_CLONE_ROOT` (default `~/code`), `AA_CURRENCY` (or write it to `~/.config/ai-agents/currency`, default USD).

Costs are estimates at Anthropic's API list prices, not your bill.

## License

MIT, see [LICENSE](LICENSE).
