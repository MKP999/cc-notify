#!/bin/bash
# Remove ClaudeNotify: stop the agent, drop the hook from settings, delete app+runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="io.github.MKP999.cc-notify"
LABEL="$BUNDLE_ID"
APP="$HOME/Applications/ClaudeNotify.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
RUNTIME="$HOME/.claude-notify"
SETTINGS="$HOME/.claude/settings.json"
MATCHER="permission_prompt|idle_prompt|agent_needs_input"
UID_N="$(id -u)"

echo "==> Stopping LaunchAgent"
launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true
pkill -f "MacOS/ClaudeNotify" 2>/dev/null || true
rm -f "$PLIST"

echo "==> Removing ClaudeNotify hook from: $SETTINGS"
if [ -f "$SETTINGS" ]; then
  tmp="$(mktemp)"
  jq --arg matcher "$MATCHER" '
    (.hooks.Notification // []) |= map(select((.matcher // "") != $matcher))
    | if ((.hooks.Notification // []) | length) == 0 then del(.hooks.Notification) else . end
    | if ((.hooks // {}) | length) == 0 then del(.hooks) else . end
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
fi

echo "==> Removing app + runtime"
rm -rf "$APP" "$RUNTIME"

echo "==> Done."
echo "    Source kept at: $ROOT"
echo "    settings.json backup: $SETTINGS.bak.claude-notify (delete if unneeded)"
