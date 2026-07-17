#!/bin/bash
# Claude Code Notification hook for ClaudeNotify.
# Reads the hook JSON from stdin, captures the Warp/tmux focus target from the
# environment, and atomically writes one event file per session to the spool dir.
# The menubar app watches that dir and surfaces a notification + click-to-focus.
#
# Registered in ~/.claude/settings.json as a "Notification" hook with matcher:
#   permission_prompt|idle_prompt|agent_needs_input
set -u

QUEUE_DIR="${CLAUDE_NOTIFY_QUEUE:-$HOME/.claude-notify/queue}"
mkdir -p "$QUEUE_DIR"

INPUT="$(cat)"

session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
# Nothing stable to key a file on — bail silently (exit 0 so we never block).
[ -z "$session_id" ] && exit 0

ntype="$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)"
msg="$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)"
cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
project="$(basename "${cwd:-unknown}")"

# Focus targets (inherited from the terminal-launched shell).
warp_url="${WARP_FOCUS_URL:-}"
warp_uuid="${WARP_TERMINAL_SESSION_UUID:-}"
term_bundle_id="${__CFBundleIdentifier:-}"   # owning terminal app (e.g. dev.warp.Warp-Stable)

tmux_socket=""
tmux_target=""
if [ -n "${TMUX:-}" ]; then
  tmux_socket="${TMUX%%,*}"   # first field of $TMUX is the server socket path
  tmux_target="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)"
fi

ts="$(date +%s)"

payload="$(jq -nc \
  --arg sid "$session_id" \
  --arg type "$ntype" \
  --arg msg "$msg" \
  --arg cwd "$cwd" \
  --arg project "$project" \
  --arg warp_url "$warp_url" \
  --arg warp_uuid "$warp_uuid" \
  --arg term_bundle_id "$term_bundle_id" \
  --arg tmux_socket "$tmux_socket" \
  --arg tmux_target "$tmux_target" \
  --argjson ts "$ts" \
  '{session_id:$sid, notification_type:$type, message:$msg, cwd:$cwd, project:$project,
    warp_url:$warp_url, warp_uuid:$warp_uuid, term_bundle_id:$term_bundle_id,
    tmux_socket:$tmux_socket, tmux_target:$tmux_target, ts:$ts}')"

# Atomic write: temp file in the same directory, then rename.
tmp="$QUEUE_DIR/.tmp.$$"
printf '%s\n' "$payload" > "$tmp" && mv -f "$tmp" "$QUEUE_DIR/${session_id}.json"
exit 0
