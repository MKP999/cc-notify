import Foundation

/// One Claude Code "waiting for user" event, decoded leniently from a spool file.
/// The hook writes one file per session (filename = session_id), latest overwrites.
struct ClaudeEvent {
    let session_id: String
    let notification_type: String
    let message: String
    let cwd: String
    let project: String
    let warp_url: String        // "warp://session/<uuid>" or ""
    let warp_uuid: String
    let term_bundle_id: String  // owning terminal's bundle id (e.g. dev.warp.Warp-Stable) or ""
    let tmux_socket: String     // tmux server socket or ""
    let tmux_target: String     // "session:window.pane" or ""
    let ts: Double              // epoch seconds
}

extension ClaudeEvent {
    /// Human-readable reason in Chinese, derived from notification_type.
    var reasonText: String {
        switch notification_type {
        case "permission_prompt":   return "需要授权"
        case "idle_prompt":         return "等待输入"
        case "agent_needs_input":   return "Agent 等待输入"
        case "":                    return "需要关注"
        default:                    return notification_type
        }
    }

    /// Lenient loader: tolerates missing keys (treats them as ""/0).
    static func load(from url: URL) -> ClaudeEvent? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard let sid = raw["session_id"] as? String, !sid.isEmpty else { return nil }
        func s(_ k: String) -> String { (raw[k] as? String) ?? "" }
        let ts: Double = {
            if let n = raw["ts"] as? Double { return n }
            if let str = raw["ts"] as? String, let n = Double(str) { return n }
            return 0
        }()
        let project = s("project").isEmpty ? (s("cwd") as NSString).lastPathComponent : s("project")
        return ClaudeEvent(
            session_id: sid,
            notification_type: s("notification_type"),
            message: s("message"),
            cwd: s("cwd"),
            project: project,
            warp_url: s("warp_url"),
            warp_uuid: s("warp_uuid"),
            term_bundle_id: s("term_bundle_id"),
            tmux_socket: s("tmux_socket"),
            tmux_target: s("tmux_target"),
            ts: ts
        )
    }
}
