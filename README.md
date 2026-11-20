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

Needs macOS, [Claude Code](https://claude.com/claude-code), `tmux`, `fzf` (recent; tested with 0.75), `jq`, `git` and the GitHub CLI `gh` (logged in). iTerm2 is optional.

```sh
brew install tmux fzf jq gh
git clone https://github.com/juhasztibi/agent-supervisor ~/Projects/agent-supervisor
ln -s ~/Projects/agent-supervisor/ai-agents ~/.local/bin/ai-agents   # any folder on your PATH
ai-agents selftest                                                   # about 30 seconds, touches nothing of yours
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
