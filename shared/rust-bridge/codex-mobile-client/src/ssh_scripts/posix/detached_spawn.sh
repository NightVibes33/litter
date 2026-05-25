# Spawn a long-running detached agent. The pattern:
#   1. mkfifo INPUT so a stable file descriptor exists for the agent's
#      stdin (otherwise once the SSH stdin closes, the agent dies on EOF)
#   2. nohup a "keeper" process that holds the FIFO open by reading from it
#      forever — without this, the agent's reads on stdin would EOF as soon
#      as the keeper exits
#   3. nohup the actual agent with stdin redirected from INPUT, stdout /
#      stderr to log files, and detached via setsid (where available)
# Caller passes pre-quoted absolute paths for ROOT, INPUT, OUT_LOG,
# ERR_LOG, KEEPER_PID, AGENT_PID, and a shell-quoted COMMAND.
set -eu
session_dir={{ROOT}}
mkdir -p "$session_dir"
rm -f {{INPUT}}
mkfifo {{INPUT}}
: > {{OUT_LOG}}
: > {{ERR_LOG}}
nohup sh -c 'exec 0<>"$1"; while :; do sleep 3600; done' sh {{INPUT}} </dev/null >/dev/null 2>&1 &
echo $! > {{KEEPER_PID}}
if command -v setsid >/dev/null 2>&1; then
  nohup setsid /usr/bin/env sh -c {{COMMAND}} < {{INPUT}} > {{OUT_LOG}} 2> {{ERR_LOG}} &
else
  nohup /usr/bin/env sh -c {{COMMAND}} < {{INPUT}} > {{OUT_LOG}} 2> {{ERR_LOG}} &
fi
agent_pid=$!
echo "$agent_pid" > {{AGENT_PID}}
printf '%s\n' "$agent_pid"
