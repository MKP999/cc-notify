import AppKit
import Foundation

/// Brings the originating terminal session to the foreground.
/// Order of preference: Warp deep link → tmux pane → just activate Warp.
enum Focuser {
    static func focus(_ event: ClaudeEvent) {
        if !event.warp_url.isEmpty, let url = URL(string: event.warp_url) {
            NSWorkspace.shared.open(url)
            return
        }
        if !event.tmux_target.isEmpty {
            var base = ["tmux"]
            if !event.tmux_socket.isEmpty { base += ["-S", event.tmux_socket] }
            // Move the attached client's view to the pane, then select it.
            run(base + ["select-window", "-t", event.tmux_target])
            run(base + ["select-pane", "-t", event.tmux_target])
            run(base + ["switch-client", "-t", event.tmux_target])
            activateTerminal(event.term_bundle_id)
            return
        }
        // No precise target — surface the terminal that owns the session.
        activateTerminal(event.term_bundle_id)
    }

    /// Bring the owning terminal app to the foreground by bundle id.
    /// Works for any macOS terminal (iTerm2, Terminal.app, Ghostty, …);
    /// no-op when no bundle id is known, rather than guessing/launching one.
    static func activateTerminal(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateAllWindows])
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func run(_ argv: [String]) {
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = argv
        try? p.run()
        p.waitUntilExit()
    }
}
