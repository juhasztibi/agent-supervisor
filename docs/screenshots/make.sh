#!/usr/bin/env bash
# Makes the README screenshots from a demo setup: its own tmux server, a fake Claude Code and GitHub,
# and a made-up organisation "acme". Nothing of yours is used or shown.
# Run: docs/screenshots/make.sh   (about a minute; writes the SVG files next to this script)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
A="$(cd "$HERE/../.." && pwd)/ai-agents"
REAL_TMUX=$(command -v tmux) || { echo "tmux is missing"; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/aa-shots.XXXXXX"); SOCK="aa-shots-$$"
cleanup() { "$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null; pkill -f "$T/" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
mkdir -p "$T"/{bin,repos,wt,cfg,cache,projects}

cat > "$T/bin/tmux" <<EOF
#!/bin/bash
exec "$REAL_TMUX" -L "$SOCK" "\$@"
EOF
cat > "$T/bin/osascript" <<'EOF'
#!/bin/bash
cat >/dev/null
EOF
cat > "$T/bin/docker" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$T/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "api user")       printf 'dev\tyour own repositories\n' ;;
  "api --paginate") printf 'acme\tAcme Inc.\nacme-labs\tExperiments\n' ;;
  "repo list")      printf 'api\tBackend API\nweb\tWeb app\ndocs\tDocumentation site\nmobile\tiOS and Android app\npayments\tPayment service\n' ;;
  *)                exit 1 ;;
esac
EOF
cat > "$T/bin/claude" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "auth status") echo '{"loggedIn": true, "email": "dev@example.com", "orgName": "Acme", "subscriptionType": "team", "loginExpiresAt": "$(date -u -v+27d +%Y-%m-%dT%H:%M:%S.000Z)"}'; exit 0 ;;
  "--version ")  echo "2.1.330 (Claude Code)"; exit 0 ;;
  "plugin list") echo '[]'; exit 0 ;;
esac
exec sleep 100000
EOF
chmod +x "$T/bin/"*

for r in api web docs; do
  git init -q --bare "$T/repos/$r.git"
  git clone -q "$T/repos/$r.git" "$T/repos/$r" 2>/dev/null
  git -C "$T/repos/$r" -c user.email=d@e -c user.name=d -c commit.gpgsign=false commit -q --allow-empty -m init
  git -C "$T/repos/$r" push -q origin HEAD 2>/dev/null
  git -C "$T/repos/$r" remote set-head origin -a >/dev/null 2>&1
done

export PATH="$T/bin:$PATH" AA_WT_ROOT="$T/wt" AA_CONFIG_DIR="$T/cfg" XDG_CACHE_HOME="$T/cache" AA_CLONE_ROOT="$T/clones" \
  AA_REPO_ROOTS="$T/repos" AA_CLAUDE_PROJECTS="$T/projects" AA_OPEN=detached AA_CURRENCY=USD AA_STUCK_SEC=99999 \
  AA_REMIND_SEC=99999 AA_ANSWER_SEC=99999 AA_WAIT_SEC=99999 AA_DELIVER_SEC=99999 COLORFGBG='15;0'
unset TMUX CLAUDECODE AA_ORG AA_PREFIX
tmux new-session -d -s boot
tmux set -g default-command "/bin/bash --noprofile --norc"
for v in PATH AA_WT_ROOT AA_CONFIG_DIR XDG_CACHE_HOME AA_CLONE_ROOT AA_REPO_ROOTS AA_CLAUDE_PROJECTS AA_OPEN AA_CURRENCY; do
  tmux set-environment -g "$v" "${!v}"
done

"$A" org acme >/dev/null
"$A" add-repo "$T/repos/api" api "Backend API" >/dev/null
"$A" add-repo "$T/repos/web" web "Web app" >/dev/null
"$A" add-repo "$T/repos/docs" docs "Documentation site" >/dev/null
"$A" up checkout-redesign --only api,web --goal "Redesign the checkout summary" >/dev/null 2>&1
"$A" up login-timeout --only api --goal "Fix the login timeout" >/dev/null 2>&1
sleep 3

W="$T/wt"; now=$(date +%s)
pdir() { echo "$T/projects/$(printf '%s' "$(cd "$W/$1/$2" && pwd -P)" | sed 's/[^A-Za-z0-9]/-/g')"; }
reply() { # <task> <repo> <tokens> <content json>: one assistant reply in that agent's session file
  mkdir -p "$(pdir "$1" "$2")"
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"m%s","model":"claude-opus-5-5","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s},"content":[%s]}}\n' \
    "$(date -u -r $((now - 60)) +%Y-%m-%dT%H:%M:%S.000Z)" "$RANDOM" "$3" "$(($3 / 8))" "$(($3 * 6))" "$4" >> "$(pdir "$1" "$2")/s.jsonl"
}
reply checkout-redesign api 180000 "{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Edit\",\"input\":{\"file_path\":\"$W/checkout-redesign/api/src/orders/summary.ts\"}}"
reply checkout-redesign web 140000 '{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"pnpm test checkout","description":"Run the checkout tests"}}'
reply login-timeout api 90000 '{"type":"text","text":"Fixed the timeout: sessions now refresh **5 minutes** before they expire. Opened [PR #42](https://github.com/acme/api/pull/42)."}'
printf 'working\t%s\tEdit: src/orders/summary.ts\n' $((now - 40)) > "$W/checkout-redesign/api.state"
printf 'needs-you\t%s\tBash: pnpm test checkout\n' $((now - 180)) > "$W/checkout-redesign/web.state"
printf 'idle\t%s\tfinished its turn\n' $((now - 300)) > "$W/login-timeout/api.state"
mkdir -p "$W/checkout-redesign/web/src"; echo "x" > "$W/checkout-redesign/web/src/Summary.tsx"
git -C "$W/checkout-redesign/api" -c user.email=d@e -c user.name=d -c commit.gpgsign=false commit -q --allow-empty -m "Order summary endpoint"
AA_TASK=checkout-redesign AA_AGENT=api "$A" handoff web "GET /orders/:id/summary returns {items, totals, currency}" >/dev/null 2>&1
AA_TASK=checkout-redesign AA_AGENT=web "$A" ask api "Are totals in cents?" >/dev/null 2>&1
for r in web api; do echo '{}' | "$A" _hook checkout-redesign "$r" PostToolUse; done   # the agents read their messages
printf 'working\t%s\tEdit: src/orders/summary.ts\n' $((now - 40)) > "$W/checkout-redesign/api.state"
printf 'needs-you\t%s\tBash: pnpm test checkout\n' $((now - 180)) > "$W/checkout-redesign/web.state"
mkdir -p "$T/cache/ai-agents/orgs/acme"
printf 'api\tlogin-timeout\t42\tOPEN\tpass\thttps://github.com/acme/api/pull/42\n' > "$T/cache/ai-agents/orgs/acme/prs.tsv"

shot() { # <name> <title>: the screen as it is now
  tmux capture-pane -e -p -t shots > "$T/$1.ans"
  [[ -z "${KEEP:-}" ]] || cp "$T/$1.ans" "$KEEP/"   # KEEP=<folder>: also keep the raw captures
  python3 "$HERE/ansi2svg.py" "$T/$1.ans" "$HERE/$1.svg" "$2"
  echo "wrote docs/screenshots/$1.svg"
}
tmux new-session -d -s shots -x 112 -y 32 "env -u AA_ORG AA_OPEN=window $A"
sleep 4; shot organisations "ai-agents: pick an organisation"
tmux send-keys -t shots Enter; sleep 9; shot overview "ai-agents: overview"
tmux send-keys -t shots m; sleep 10; shot monitor "ai-agents: Monitor"
tmux send-keys -t shots Escape; sleep 3
tmux send-keys -t shots 1; sleep 3; tmux send-keys -t shots Enter; sleep 2
tmux send-keys -t shots dark-mode Enter; sleep 4
tmux send-keys -t shots Space; sleep 0.5; tmux send-keys -t shots Down Space; sleep 1
shot start "ai-agents: start agents"

# the tmux status bar, as it looks with "#(ai-agents status)" in status-right
st=$("$A" status | sed -e 's/#\[fg=yellow,bold\]/\x1b[33;1m/g' -e 's/#\[fg=green\]/\x1b[32m/g' -e 's/#\[default\]/\x1b[0m/g')
printf '\x1b[48;5;111m\x1b[38;5;235;1m dark-mode \x1b[0m\x1b[48;5;235m %-52s %s  \x1b[38;5;139m14:32 \x1b[0m\n' "0:api  1:web  2:srv" "$st" > "$T/status.ans"
python3 "$HERE/ansi2svg.py" "$T/status.ans" "$HERE/status-bar.svg" "tmux status bar"; echo "wrote docs/screenshots/status-bar.svg"
