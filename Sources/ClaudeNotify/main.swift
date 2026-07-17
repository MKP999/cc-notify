import AppKit

// Entry point for the ClaudeNotify menubar app.
// A background, menu-bar-only helper (accessory activation policy) that watches
// ~/.claude-notify/queue/ for Claude Code "waiting for user" events, posts native
// macOS notifications, and focuses the originating Warp/tmux session on click.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
