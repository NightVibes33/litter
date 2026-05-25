# Stop the opencode process spawned for a session. Port cleanup is handled by
# the caller with the shared kill-port probe so this script can stay pid-scoped.
{{PROFILE_INIT}}
session_dir="$HOME/.litter/sessions/{{SESSION_ID}}"
pid_file="$session_dir/agent.pid"
if [ ! -f "$pid_file" ]; then
  exit 0
fi
pid="$(cat "$pid_file" 2>/dev/null || true)"
case "$pid" in
  ""|*[!0-9]*)
    rm -f "$pid_file"
    exit 0
    ;;
esac
kill "$pid" 2>/dev/null || true
sleep 0.2
if kill -0 "$pid" 2>/dev/null; then
  kill -9 "$pid" 2>/dev/null || true
fi
rm -f "$pid_file"
