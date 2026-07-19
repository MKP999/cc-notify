# cc-notify — Claude Code 多会话「等待提醒 + 点击跳转」

菜单栏小铃铛：任何一个 Claude Code 会话卡住等你操作（需要授权 / 空闲等待 / 后台 agent 等输入）时弹横幅，点击横幅或菜单项直接跳到那个会话。

## 它解决什么问题
你同时开了多个 Claude Code，某个会话卡住需要确认时，你在别的会话里完全没感知。终端自带的通知只在**当前那个会话内部**显示，跨会话看不到。本工具补上「跨会话桌面提醒 + 点击跳转」。

## 支持平台 / 终端
**仅支持 macOS 13+。**（整个通知 + 菜单栏 + 跳转架构基于 Swift / AppKit / `UNUserNotificationCenter`，是 macOS 专属。Windows / Linux 暂不支持，欢迎 PR。）

点击跳转的精度取决于终端：

| 终端 | 跳转精度 |
| :-- | :-- |
| Warp | 精确跳到该会话（`warp://session/<uuid>` 深链） |
| tmux（任意终端内） | 精确切到对应 pane（`switch-client`），终端无关、最可靠 |
| 其它 Mac 终端（iTerm2 / Terminal.app / Ghostty / Kitty / WezTerm …） | 激活该终端 App 到前台（不定位具体 tab） |

> 想要 100% 可靠的「点哪跳哪」？在 **tmux** 里跑 Claude 即可，与终端无关。

## 工作原理
```
Claude 卡住 → Claude Code 的 Notification hook → 原子写 ~/.claude-notify/queue/<session_id>.json
   → 菜单栏 App 监听目录 → 角标 + 列表 + 原生横幅
   → 点击 → 用 warp:// 深链 或 tmux 切 pane 或激活终端 → 清除该条
```
- 一个 session 一个文件 = 菜单栏列表一项（文件系统天然去重 + 持久化，App 重启扫目录即恢复）。
- **没点击会长驻**：菜单栏角标 + 列表一直挂到，直到你点它（跳转+清除）或「全部清除」；无自动过期；重启不丢。
- 触发事件（matcher）：`permission_prompt`（需授权）、`idle_prompt`（空闲等待）、`agent_needs_input`（后台 agent 等输入）。

## 安装
需要 macOS 13+、Xcode Command Line Tools（`swift` / `jq` / `codesign` / `sips` / `iconutil`）。

```bash
git clone https://github.com/MKP999/cc-notify.git
cd cc-notify
./install.sh
```
首次：按系统弹窗授权通知（或 系统设置 → 通知 → Claude Notify → 允许）。

`install.sh` 会：构建 release 二进制 → 程序化生成图标 → 打 `.app` bundle 并 ad-hoc 签名 → 装 hook 脚本与 queue 目录 → 在 `~/.claude/settings.json` 注册 `Notification` hook → 装 LaunchAgent 常驻。

## 测试
不用真开 Claude，直接丢一个事件文件：
```bash
cat > ~/.claude-notify/queue/test.json <<'JSON'
{"session_id":"manual-test","notification_type":"permission_prompt","message":"点击我","cwd":"/tmp","project":"ManualTest","warp_url":"","warp_uuid":"","term_bundle_id":"","tmux_socket":"","tmux_target":"","ts":0}
JSON
```
菜单栏铃铛应出现角标并弹横幅。点菜单栏铃铛 →「发送测试通知」可单独验证横幅；要测点击跳转，把 `warp_url` 设成你真实的 `$WARP_FOCUS_URL`（Warp）或在 tmux 里跑。

## 真实联调
在一个 Claude 会话里让它执行需要授权的命令（触发 `permission_prompt`）→ 另一会话能看到横幅 + 角标 → 点击跳过去。

## 关于通知横幅图标
菜单栏铃铛和通知横幅都会显示程序化生成的黏土色铃铛图标（随 `install.sh` 生成并打包进 `.app`）。
- 首次需在「系统设置 → 通知 → Claude Notify」开启通知权限，横幅才会出现。
- 极少数情况下若 LaunchServices 图标缓存导致横幅图标不显示，标题前的 🔔 emoji 仍能一眼识别。

## 卸载
```bash
./uninstall.sh
```
会从 `~/.claude/settings.json` 移除 hook、停 LaunchAgent、删 App 和运行时目录（源码保留）。

## 文件布局
| 位置 | 说明 |
| :-- | :-- |
| 源码（本仓库） | `Package.swift`、`Sources/ClaudeNotify/*.swift`、`hook.sh`、`install.sh`、`uninstall.sh`、`tools/make-icon.swift`、`templates/Info.plist` |
| `~/.claude-notify/` | 运行时：`hook.sh`、`queue/`、`app.log` |
| `~/Applications/ClaudeNotify.app` | 安装后的 App bundle |
| `~/Library/LaunchAgents/io.github.MKP999.cc-notify.plist` | 常驻 LaunchAgent |
| `~/.claude/settings.json` | 仅新增 `hooks.Notification` 一项（卸载会还原，备份在 `settings.json.bak.claude-notify`） |

## 配置点
- 触发事件：改 `~/.claude/settings.json` 里 hook 的 `matcher`。
- 横幅限频：`AppDelegate.swift` 的 `bannerCooldown`（默认 10s/会话）。
- 图标：改 `tools/make-icon.swift`（颜色/图形）后重跑 `./install.sh`。
