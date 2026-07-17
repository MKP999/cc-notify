#!/bin/bash
# Build & install ClaudeNotify — a menu-bar helper that alerts you when any
# Claude Code session is waiting on you, and jumps to that session on click.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="io.github.MKP999.cc-notify"
LABEL="$BUNDLE_ID"
APP="$HOME/Applications/ClaudeNotify.app"
RUNTIME="$HOME/.claude-notify"
HOOK="$RUNTIME/hook.sh"
QUEUE="$RUNTIME/queue"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SETTINGS="$HOME/.claude/settings.json"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
MATCHER="permission_prompt|idle_prompt|agent_needs_input"

echo "==> Checking tools"
for t in swift jq codesign sips iconutil; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: missing required tool: $t"; exit 1; }
done

echo "==> swift build -c release"
cd "$ROOT"
swift build -c release
BIN="$ROOT/.build/release/ClaudeNotify"
[ -f "$BIN" ] || { echo "ERROR: build output not found: $BIN"; exit 1; }

echo "==> Generating app icon"
ICONDIR="$ROOT/.build/icon"
ICONSRC="$ICONDIR/icon_1024.png"
ICNS="$ICONDIR/AppIcon.icns"
mkdir -p "$ICONDIR"
swift "$ROOT/tools/make-icon.swift" "$ICONSRC"
ICONSET="$ICONDIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" \
            "512:icon_512x512" "1024:icon_512x512@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" "$ICONSRC" --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Assembling bundle: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeNotify"
cp "$ROOT/templates/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
# Fresh build version on every install so LaunchServices re-reads the icon.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%s)" "$APP/Contents/Info.plist"

echo "==> Ad-hoc codesign"
codesign --force --deep -s - "$APP"

echo "==> Installing runtime: $RUNTIME"
mkdir -p "$QUEUE"
cp "$ROOT/hook.sh" "$HOOK"
chmod +x "$HOOK"

echo "==> Registering Notification hook in: $SETTINGS"
if [ -f "$SETTINGS" ]; then cp -p "$SETTINGS" "$SETTINGS.bak.claude-notify"; fi
HOOK_CMD='$HOME/.claude-notify/hook.sh'
tmp="$(mktemp)"
jq --arg cmd "$HOOK_CMD" --arg matcher "$MATCHER" '
  .hooks.Notification = (
    ((.hooks.Notification // []) | map(select((.matcher // "") != $matcher)))
    + [{ "matcher": $matcher,
         "hooks": [ { "type": "command", "command": $cmd, "timeout": 10 } ] }]
  )
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

echo "==> Installing LaunchAgent: $PLIST"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-W</string>
    <string>-g</string>
    <string>$APP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$RUNTIME/app.log</string>
  <key>StandardErrorPath</key><string>$RUNTIME/app.log</string>
</dict>
</plist>
EOF

UID_N="$(id -u)"
launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true
pkill -f "ClaudeNotify.app/Contents/MacOS/ClaudeNotify" 2>/dev/null || true
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -f "$APP" 2>/dev/null || true
launchctl bootstrap "gui/$UID_N" "$PLIST"

# Refresh icon / notification caches so the new app icon shows immediately.
sleep 2
killall usernoted 2>/dev/null || true

cat <<DONE

==> Installed. ClaudeNotify is running (look for the bell in the menu bar).

First-time setup:
  • Grant notification permission when prompted, or:
    System Settings → Notifications → "Claude Notify" → Allow.
  • If the bell doesn't appear, launch once manually:
    open "$APP"

Test it (no Claude Code needed):
  cat > "$QUEUE/test.json" <<'JSON'
  {"session_id":"manual-test","notification_type":"permission_prompt","message":"点击我跳转","cwd":"$HOME","project":"ManualTest","warp_url":"$WARP_FOCUS_URL","warp_uuid":"","tmux_socket":"","tmux_target":"","ts":0}
  JSON
  (set warp_url to your actual warp://session/... to test click-to-focus)

Logs:   tail -f "$RUNTIME/app.log"
Remove: "$ROOT/uninstall.sh"
DONE
