import AppKit
import UserNotifications
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    // MARK: - Config
    private let queueDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude-notify/queue", isDirectory: true)
    }()
    /// Min seconds between banners for the same session (anti-spam).
    private let bannerCooldown: TimeInterval = 10
    /// Safety-net reconciliation interval (DispatchSource events can coalesce).
    private let pollInterval: TimeInterval = 3

    // MARK: - State
    private var statusItem: NSStatusItem!
    /// session_id -> (event, file mtime)
    private var sessions: [String: (ClaudeEvent, Date)] = [:]
    private var lastBanner: [String: Date] = [:]
    private var dirSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        rebuildStatusItem()
        startWatching()
        rescan(initial: true)

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.rescan(initial: false)
        }
    }

    // MARK: - Menu bar
    private func rebuildStatusItem() {
        let count = sessions.count
        let button = statusItem.button
        button?.image = NSImage(systemSymbolName: count > 0 ? "bell.fill" : "bell",
                                accessibilityDescription: "Claude Code alerts")
        button?.title = count > 0 ? "  \(count)" : ""

        let menu = NSMenu()
        menu.autoenablesItems = false

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "无待处理会话", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (_, value) in sessions.sorted(by: { $0.value.1 > $1.value.1 }) {
                let e = value.0
                let item = NSMenuItem(title: "\(e.project) — \(e.reasonText) · \(relativeTime(value.1))",
                                      action: #selector(focusAndClear(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = e.session_id
                item.toolTip = "\(e.message)\n\(e.cwd)"
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        addItem(menu, "全部清除", #selector(clearAll(_:)))
        addItem(menu, "发送测试通知", #selector(sendTest(_:)))
        addItem(menu, "退出 ClaudeNotify", #selector(quit(_:)), key: "q")
        statusItem.menu = menu
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func focusAndClear(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String, let value = sessions[sid] else { return }
        Focuser.focus(value.0)
        clearSession(sid)
    }

    @objc private func clearAll(_ sender: Any) {
        for sid in Array(sessions.keys) { clearSession(sid) }
    }

    @objc private func sendTest(_ sender: Any) {
        let env = ProcessInfo.processInfo.environment
        let e = ClaudeEvent(
            session_id: "test-\(Int(Date().timeIntervalSince1970))",
            notification_type: "permission_prompt",
            message: "这是一条测试通知（点击应跳转到本 Warp 会话）",
            cwd: FileManager.default.currentDirectoryPath,
            project: "TestProject",
            warp_url: env["WARP_FOCUS_URL"] ?? "",
            warp_uuid: env["WARP_TERMINAL_SESSION_UUID"] ?? "",
            term_bundle_id: env["__CFBundleIdentifier"] ?? "",
            tmux_socket: "", tmux_target: "",
            ts: Date().timeIntervalSince1970
        )
        postBanner(e)
    }

    @objc private func quit(_ sender: Any) {
        // Under the launchd agent (KeepAlive), terminate alone is instantly
        // undone by a relaunch. Boot our own agent out first so it stays quit;
        // fails harmlessly when the app isn't running under launchd.
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["bootout", "gui/\(getuid())/io.github.MKP999.cc-notify"]
        try? p.run()
        NSApp.terminate(nil)
    }

    private func clearSession(_ sid: String) {
        try? FileManager.default.removeItem(at: queueDir.appendingPathComponent("\(sid).json"))
        sessions.removeValue(forKey: sid)
        rebuildStatusItem()
    }

    // MARK: - Directory watching
    private func startWatching() {
        let fd = open(queueDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.rescan(initial: false) }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    /// Re-read queue dir; post banners for new/updated sessions; refresh menu only on change.
    private func rescan(initial: Bool) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: queueDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else {
            if !sessions.isEmpty { sessions.removeAll(); rebuildStatusItem() }
            return
        }

        var seen: [String: (ClaudeEvent, Date)] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let ev = ClaudeEvent.load(from: url) else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date()
            seen[ev.session_id] = (ev, mtime)
        }

        var changed = initial
        for (sid, value) in seen {
            let prev = sessions[sid]
            let isFresh = prev == nil || prev!.1 != value.1
            if isFresh {
                changed = true
                if !initial {
                    let last = lastBanner[sid] ?? .distantPast
                    if Date().timeIntervalSince(last) >= bannerCooldown {
                        postBanner(value.0)
                        lastBanner[sid] = Date()
                    }
                }
            }
        }
        for sid in sessions.keys where seen[sid] == nil { changed = true }

        sessions = seen
        if changed { rebuildStatusItem() }
    }

    // MARK: - Notifications
    private func postBanner(_ e: ClaudeEvent) {
        let content = UNMutableNotificationContent()
        // macOS 14+ won't render a custom app icon for unsigned/ad-hoc apps in
        // the banner, so prefix the title with a bell emoji for visual identity.
        content.title = "🔔 Claude ▸ \(e.project)"
        content.subtitle = e.reasonText
        content.body = e.message.isEmpty ? e.reasonText : e.message
        content.sound = .default
        content.userInfo = [
            "session_id": e.session_id,
            "warp_url": e.warp_url,
            "term_bundle_id": e.term_bundle_id,
            "tmux_socket": e.tmux_socket,
            "tmux_target": e.tmux_target,
            "cwd": e.cwd,
            "project": e.project
        ]
        let req = UNNotificationRequest(
            identifier: "claude-\(e.session_id)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let info = response.notification.request.content.userInfo
            let sid = (info["session_id"] as? String) ?? ""
            if !sid.isEmpty {
                let e = ClaudeEvent(
                    session_id: sid,
                    notification_type: "",
                    message: "",
                    cwd: (info["cwd"] as? String) ?? "",
                    project: (info["project"] as? String) ?? "",
                    warp_url: (info["warp_url"] as? String) ?? "",
                    warp_uuid: "",
                    term_bundle_id: (info["term_bundle_id"] as? String) ?? "",
                    tmux_socket: (info["tmux_socket"] as? String) ?? "",
                    tmux_target: (info["tmux_target"] as? String) ?? "",
                    ts: Date().timeIntervalSince1970
                )
                Focuser.focus(e)
                clearSession(sid)
            }
        }
        completionHandler()
    }

    // MARK: - Helpers
    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
