# EvilStore — UI 设计与 ASCII 线框（3 号文档）

> 版本：v0.1（开工前最后一份文档）
> 日期：2026-05-05
> 前置：1 号 v0.3 + 2 号 v0.3 必读
>
> **本文档定位**：把 1 号文档里抽象描述的 UI 子树（Search / Detail / Downloads / Library / Settings / Login / Onboarding）落成可视的 ASCII 线框稿，确认信息架构、屏间跳转、空态/错误态、关键 modal 的样子。审查通过后即开工 M0。

---

## 目录

- [0. 设计原则](#0-设计原则)
- [1. 信息架构总图](#1-信息架构总图)
- [2. Onboarding — 首次启动三步](#2-onboarding--首次启动三步)
- [3. Manual Login — Stealth 失败兜底](#3-manual-login--stealth-失败兜底)
- [4. Tab 1: Search](#4-tab-1-search)
- [5. Tab 2: App Detail — 版本时间轴（核心）](#5-tab-2-app-detail--版本时间轴核心)
- [6. Tab 3: Downloads](#6-tab-3-downloads)
- [7. Tab 4: Library](#7-tab-4-library)
- [8. Tab 5: Settings](#8-tab-5-settings)
- [9. 全局 Modal / Alert](#9-全局-modal--alert)
- [10. 用户主流程图](#10-用户主流程图)
- [11. 视觉规范](#11-视觉规范)
- [12. 无障碍](#12-无障碍)
- [13. 文案语言策略](#13-文案语言策略)
- [14. 待办与开放问题](#14-待办与开放问题)

---

## 0. 设计原则

1. **暗色优先**。TrollStore 用户夜里用得多；亮色作 follow-up，不优先打磨。
2. **信息密度高于花哨**。这是工具，不是消费品。每屏首要回答用户当下的问题（"哪一版？多大？装上没？"），其它放 detail 页。
3. **一屏一目的**。不在 Search 页放 Settings 入口，不在 Detail 页堆"相关 App"。Tab Bar 是唯一全局导航。
4. **iOS 14 baseline**（见 1 号文档 §2.6）。所有线框都用 iOS 14 上能跑的控件——`NavigationView` 而非 `NavigationStack`，自写 search bar 而非 `.searchable`，Kingfisher 而非 `AsyncImage`。
5. **错误显形**。Apple storefront 的失败码 / TrollStore 安装错误码（179、180、171、175、182、184）每一种都有专属文案，不抛"unknown error"给用户。
6. **隐私可见**。GUID、DSID、passwordToken 在 UI 里可看见时**永远部分遮蔽**（如 `2113xxxxxxxx`、`F3A1•••••EC72`），用户主动点"reveal"才完整显示，且 reveal 操作有审计 log。
7. **零追踪**。无 analytics、无 crash-report-as-a-service、无网络埋点。所有出口请求只去 `*.itunes.apple.com`。
8. **本地化文案 EN-first**。源串英文，`zh-Hans` 是翻译。这与 §7.7 "对外文本简洁英文"一致。本文档线框图中的文本即源串。

---

## 1. 信息架构总图

```
┌──────────────────────────────────────────────────────────────┐
│                          EvilStore                           │
└─┬────────────────────────────────────────────────────────────┘
  │
  ├─ first launch ─► Onboarding (3 steps)
  │                  │
  │                  ├─ 2.1 Risk acknowledgement
  │                  ├─ 2.2 Stealth probe
  │                  └─ 2.3 Result branch
  │                       ├─ ok    ─► Main
  │                       └─ fail  ─► Manual Login (§3)
  │
  └─ Main (TabView)
       │
       ├─ ●  Search       (§4)
       │     └─ row tap    ─► App Detail (§5)
       │
       ├─ ●  Downloads    (§6)
       │     └─ row tap    ─► Install confirm modal (§9.1)
       │
       ├─ ●  Library      (§7)
       │     └─ row tap    ─► Install / Delete / Share
       │
       └─ ●  Settings     (§8)
             ├─ Account picker
             ├─ Device GUID detail
             ├─ Stealth diagnostics (debug-only entry)
             ├─ Storage
             ├─ Logs
             └─ About / License
```

**Tab 顺序固定**：`Search → Downloads → Library → Settings`。**没有** "Home"、"For You"、"Discover" 这种消费向 tab——本工具不是 store。

---

## 2. Onboarding — 首次启动三步

只在 `UserDefaults["onboarded"] == nil` 时显示。一次性，看完不可回访（除非清缓存）。

### 2.1 Risk acknowledgement

```
┌──────────────────────────────────────────────────┐
│ 9:41                          ●●●●          100% │
├──────────────────────────────────────────────────┤
│                                                  │
│                                                  │
│                                                  │
│                  ┌──────────┐                    │
│                  │EvilStore │                    │
│                  └──────────┘                    │
│              ━━━━━━━━━━━━━━━━━━                  │
│        offline App Store companion               │
│                for TrollStore                    │
│                                                  │
│                                                  │
│  Before you begin                                │
│                                                  │
│  • Use a secondary Apple ID, not your main one.  │
│  • Activation Lock risks are real if Apple       │
│    flags the account. We will not unlock it     │
│    for you.                                      │
│  • Your device GUID is treated like a password.  │
│    Do not share it.                              │
│                                                  │
│  No data leaves this device.                     │
│                                                  │
│                                                  │
│      ┌──────────────────────────────────┐        │
│      │     I understand. Continue       │        │
│      └──────────────────────────────────┘        │
│                                                  │
└──────────────────────────────────────────────────┘
```

**交互**：唯一按钮，点击进 §2.2。无 "Skip" / "Maybe later"——用户必须显式点过 "I understand" 我们才往下走。

### 2.2 Stealth probe — 实时进度

```
┌──────────────────────────────────────────────────┐
│ 9:41                          ●●●●          100% │
├──────────────────────────────────────────────────┤
│                                                  │
│                                                  │
│                                                  │
│                   ◐  probing                     │
│                                                  │
│      reading session from system App Store       │
│                                                  │
│                                                  │
│      ┌────────────────────────────────────┐      │
│      │                                    │      │
│      │  [✓]  accountsd available          │      │
│      │  [✓]  DSID  2113xxxxxxxx           │      │
│      │  [·]  cookies  parsing 4...        │      │
│      │  [ ]  passwordToken                │      │
│      │                                    │      │
│      └────────────────────────────────────┘      │
│                                                  │
│                                                  │
│                                                  │
│                                                  │
│              skip and login manually             │
│                                                  │
└──────────────────────────────────────────────────┘
```

**符号约定**：
- `[✓]` 已成功
- `[·]` 进行中（动画 spinner）
- `[ ]` 未开始
- `[✗]` 失败

**底部** "skip and login manually" 是文字按钮（不是粗描边的 primary CTA）。让用户一直在 stealth 上耗时间是无礼的。

### 2.3 结果分支

**成功**（任一路径成功）：

```
┌──────────────────────────────────────────────────┐
│                                                  │
│                                                  │
│                                                  │
│                       ✓                          │
│                                                  │
│                  signed in as                    │
│                                                  │
│           evil0ctal_alt@icloud.com               │
│              storefront US                       │
│              borrowed from system                │
│                                                  │
│                                                  │
│      ┌──────────────────────────────────┐        │
│      │            Continue              │        │
│      └──────────────────────────────────┘        │
│                                                  │
│      not your account? sign out from Settings    │
│      › Apple ID first, then re-launch.           │
│                                                  │
└──────────────────────────────────────────────────┘
```

**失败**（全 4 路径都没拿到可用 session）：

```
┌──────────────────────────────────────────────────┐
│                                                  │
│                                                  │
│                       ⚠                          │
│                                                  │
│           could not borrow a session             │
│                                                  │
│      ┌────────────────────────────────────┐      │
│      │  [✗]  accountsd     denied         │      │
│      │  [✗]  filesystem    no account     │      │
│      │  [✗]  keychain      not allowed    │      │
│      │  [✗]  xpc           timeout        │      │
│      └────────────────────────────────────┘      │
│                                                  │
│   Make sure you are signed in to App Store at    │
│   Settings › Apple ID, then re-launch.           │
│                                                  │
│   Or skip system session and use manual login.   │
│                                                  │
│  ┌───────────────┐  ┌────────────────────────┐   │
│  │  re-probe     │  │  manual login          │   │
│  └───────────────┘  └────────────────────────┘   │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 3. Manual Login — Stealth 失败兜底

**入口**：§2.3 失败页的 "manual login" 按钮，或 Settings → Add manual account（§8.2）。

### 3.1 表单

```
┌──────────────────────────────────────────────────┐
│ ← cancel               Manual login              │
├──────────────────────────────────────────────────┤
│                                                  │
│   Sign in with Apple ID directly.                │
│   Use a secondary account.                       │
│                                                  │
│                                                  │
│   APPLE ID                                       │
│   ┌────────────────────────────────────────────┐ │
│   │ secondary@icloud.com                       │ │
│   └────────────────────────────────────────────┘ │
│                                                  │
│   PASSWORD                                       │
│   ┌────────────────────────────────────────────┐ │
│   │ ••••••••••••                            ◉ │ │
│   └────────────────────────────────────────────┘ │
│                                                  │
│   STOREFRONT                                     │
│   ┌────────────────────────────────────────────┐ │
│   │ US (143441)                              ▾ │ │
│   └────────────────────────────────────────────┘ │
│                                                  │
│                                                  │
│      ┌──────────────────────────────────┐        │
│      │              Sign in             │        │
│      └──────────────────────────────────┘        │
│                                                  │
│   ⓘ  Reminder: secondary account only.           │
│                                                  │
└──────────────────────────────────────────────────┘
```

`◉` = reveal toggle（按住显示明文，松开复原）；`▾` = storefront 下拉。

### 3.2 2FA 输入

签到时 Apple 返回 `MZFinance.BadLogin.Configurator_message` → 弹独立页（不是 modal，避免 keyboard 重叠）：

```
┌──────────────────────────────────────────────────┐
│ ← back            Two-factor code                │
├──────────────────────────────────────────────────┤
│                                                  │
│   Apple sent a 6-digit code to your trusted      │
│   devices.                                       │
│                                                  │
│                                                  │
│       ┌──┐ ┌──┐ ┌──┐  ┌──┐ ┌──┐ ┌──┐             │
│       │  │ │  │ │  │  │  │ │  │ │  │             │
│       └──┘ └──┘ └──┘  └──┘ └──┘ └──┘             │
│                                                  │
│                                                  │
│                                                  │
│      ┌──────────────────────────────────┐        │
│      │              Verify              │        │
│      └──────────────────────────────────┘        │
│                                                  │
│            didn't get a code? resend             │
│                                                  │
└──────────────────────────────────────────────────┘
```

**键盘**：数字键盘；自动 paste 6 位短信码。

### 3.3 错误态

| storefront 错误码 | 文案 |
|---|---|
| `failureType=5005` | "Wrong code. Try again." |
| `failureType=2034` (manual rotate fail) | "Password rejected. Did you change it recently?" |
| `customerMessage=MZFinance.AccountDisabled` | "Apple disabled this account. Use a different one." |
| 网络超时 | "Couldn't reach Apple. Check connection and retry." |

```
┌──────────────────────────────────────────────────┐
│ ← back            Two-factor code                │
├──────────────────────────────────────────────────┤
│                                                  │
│   Apple sent a 6-digit code to your trusted      │
│   devices.                                       │
│                                                  │
│       ┌──┐ ┌──┐ ┌──┐  ┌──┐ ┌──┐ ┌──┐             │
│       │ 1│ │ 2│ │ 3│  │ 4│ │ 5│ │ 6│             │
│       └──┘ └──┘ └──┘  └──┘ └──┘ └──┘             │
│                                                  │
│       ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━         │
│       ✗  wrong code. try again.                  │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 4. Tab 1: Search

### 4.1 空态（无输入）

```
┌──────────────────────────────────────────────────┐
│ Search                                       US ▾│
├──────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────┐  │
│  │  ⌕  Search the App Store                   │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│                                                  │
│                                                  │
│                                                  │
│                                                  │
│                  ─ no results ─                  │
│                                                  │
│        type a name or bundle id to search        │
│                                                  │
│        storefront: US (tap top-right to switch)  │
│                                                  │
│                                                  │
│                                                  │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search ● │ Download │  Library │  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

`US ▾` = storefront 切换（多账号时切换账号 = 切换 storefront）。

### 4.2 输入中 / 防抖

按下第 3 个字符后开始查询，500ms 防抖（与 §5.11 节流逻辑共用 `AsyncThrottle`）。

```
┌──────────────────────────────────────────────────┐
│ Search                                       US ▾│
├──────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────┐  │
│  │  ⌕  tele                                ✕  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│                  ◐ searching                     │
│                                                  │
│                                                  │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search ● │ Download │  Library │  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

### 4.3 结果列表

```
┌──────────────────────────────────────────────────┐
│ Search                                       US ▾│
├──────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────┐  │
│  │  ⌕  telegram                            ✕  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────┐ Telegram Messenger                       │
│  │ TG │ Telegram FZ-LLC                       ›  │
│  └────┘ 9.7.2 · Free · Social Networking         │
│                                                  │
│  ┌────┐ Telegraph                                │
│  │ TG │ TPG Telegraph Ltd.                    ›  │
│  └────┘ 5.1.0 · Free · News                      │
│                                                  │
│  ┌────┐ Telegram for macOS                       │
│  │ TG │ Telegram FZ-LLC                       ›  │
│  └────┘ 11.4 · Free · Social Networking          │
│                                                  │
│  ┌────┐ Telegram X                               │
│  │ TG │ Nikolai Durov                         ›  │
│  └────┘ 11.5.1 · Free · Social Networking        │
│                                                  │
│              · 8 more (scroll) ·                 │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search ● │ Download │  Library │  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

**Row tap** → §5 App Detail。

### 4.4 错误态

```
┌──────────────────────────────────────────────────┐
│  ┌────────────────────────────────────────────┐  │
│  │  ⌕  whatever                            ✕  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│                       ⚠                          │
│                                                  │
│             couldn't reach Apple                 │
│        check connection and try again            │
│                                                  │
│             ┌──────────────┐                     │
│             │    retry     │                     │
│             └──────────────┘                     │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 5. Tab 2: App Detail — 版本时间轴（核心）

> **整个产品的核心一屏**。其它页都是辅助；这一屏要把"哪个 App、有哪些历史版本、每版多新"在一屏内说清楚。

### 5.1 完整布局

```
┌──────────────────────────────────────────────────┐
│ ← Search                                       ⋯ │
├──────────────────────────────────────────────────┤
│                                                  │
│  ┌────┐                                          │
│  │    │  Telegram Messenger                      │
│  │ TG │  Telegram FZ-LLC                         │
│  │    │  9.7.2 · Free · Social Networking        │
│  └────┘  org.telegram.Telegraph                  │
│                                                  │
│  ─ versions ──────────────────── 23 total ────── │
│                                                  │
│  ●  9.7.2     latest               2026-04-30    │
│  │            ext  831776527                     │
│  │  ┌──────────────────────────────────────┐     │
│  │  │             Download                 │     │
│  │  └──────────────────────────────────────┘     │
│  │                                                │
│  ○  9.7.1                          2026-04-15    │
│  │            ext  830115998                     │
│  │                                                │
│  ○  9.7.0                          2026-04-02    │
│  │            ext  829844201                     │
│  │                                                │
│  ○  9.6.4                          2026-03-19    │
│  │            ext  828993310                     │
│  │                                                │
│  ○  9.6.3                          2026-03-08    │
│  │            ext  828441900                     │
│  │                                                │
│  ○  9.6.2                          2026-02-24    │
│  │                                                │
│  ○  9.6.1                          resolving...  │
│  │                                                │
│  ○  9.6.0                                        │
│        ┌────────────────────────────────────┐    │
│        │  load 16 older versions            │    │
│        └────────────────────────────────────┘    │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search ● │ Download │  Library │  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

### 5.2 时间轴元素拆解

```
●  9.7.2     latest               2026-04-30
│            ext  831776527
│
○  9.7.1                          2026-04-15
│
```

| 元素 | 含义 |
|---|---|
| `●` | 当前选中（点击展开 Download 按钮） |
| `○` | 未选中 |
| `│` | 时间轴竖线，连续到下一个节点 |
| `9.7.2` | `bundleShortVersionString`（来自 PartialZipReader.peek） |
| `latest` | 当前 App Store 上最新版（仅一项） |
| `2026-04-30` | `releaseDate`（来自 Info.plist） |
| `ext 831776527` | `softwareVersionExternalIdentifier`（power user 信息） |
| `resolving...` | partial zip peek 正在跑 |

### 5.3 选中态切换

点击未选中节点 → 该节点变 `●`，原 `●` 变 `○`，Download 按钮跟着移动。一次只能选一个版本。

### 5.4 Download 启动

按下 Download 后立即：
1. 把 task 加入 §6 Downloads 队列。
2. 切到 Downloads tab（`UITabBarController.selectedIndex = 1`）。
3. 不在 Detail 页显示进度——避免双视图同步状态的复杂度。

### 5.5 顶部菜单 `⋯`

```
                    ┌───────────────────────────┐
                    │  Open in App Store         │
                    │  Copy bundle id            │
                    │  Copy app id (1234567890)  │
                    │  Refresh versions          │
                    └───────────────────────────┘
```

---

## 6. Tab 3: Downloads

### 6.1 空态

```
┌──────────────────────────────────────────────────┐
│ Downloads                                        │
├──────────────────────────────────────────────────┤
│                                                  │
│                                                  │
│                                                  │
│                                                  │
│                                                  │
│              no downloads in flight              │
│                                                  │
│        pick a version on the detail page         │
│              to start a download                 │
│                                                  │
│                                                  │
│                                                  │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search   │ Download●│  Library │  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

### 6.2 队列在跑

```
┌──────────────────────────────────────────────────┐
│ Downloads                              pause  ⊕  │
├──────────────────────────────────────────────────┤
│                                                  │
│  ── in flight ────────────────────────────────── │
│                                                  │
│  ┌────┐ Telegram Messenger 9.7.2                 │
│  │ TG │ ████████████████░░░░░░░░░░░  68%         │
│  └────┘ 142 / 210 MB · 12.3 MB/s · 3s            │
│                                                ✕ │
│                                                  │
│  ┌────┐ WeChat 8.0.32                            │
│  │ WX │ queued · waiting for slot                │
│  └────┘                                        ✕ │
│                                                  │
│  ── done ─────────────────────────────────────── │
│                                                  │
│  ┌────┐ Discord 165.0                            │
│  │ DC │ patched · 124 MB · 2026-05-04 18:22      │
│  └────┘                          install   ⋯     │
│                                                  │
│  ┌────┐ X (Twitter) 10.42                        │
│  │ X  │ patched · 88 MB · 2026-05-04 11:09       │
│  └────┘                          install   ⋯     │
│                                                  │
│  ── failed ───────────────────────────────────── │
│                                                  │
│  ┌────┐ SomeApp 3.1.4                            │
│  │ SA │ failed · 9610 license required           │
│  └────┘                          retry     ⋯     │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search   │Download●(2)│Library │  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

### 6.3 进度条状态

```
[========================================]  100%   patching → done
[████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░]   30%   downloading
[░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]   0%   queued
[XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX]        failed (red)
[------------------------------]                  cancelled (grey)
```

### 6.4 单条操作菜单 `⋯`

```
                       ┌─────────────────────────┐
                       │  Install                │
                       │  Re-patch (re-inject sinf)│
                       │  Show in Files          │
                       │  Share .ipa             │
                       │  Delete                 │
                       └─────────────────────────┘
```

`Re-patch` 用于"我手贱删了 iTunesMetadata.plist 想重新跑一次 IPAPatcher"的极端场景。

### 6.5 Top-right 控件

| 控件 | 行为 |
|---|---|
| `pause` | 暂停所有 in-flight；变 `resume` |
| `⊕` | "add download by app id"（专家模式，输入 trackId 直接 enqueue） |

---

## 7. Tab 4: Library

> 区别于 Downloads：Downloads 是临时队列，Library 是持久化的 IPA 收藏。同一个 App 的多版本在这里聚合显示。

### 7.1 空态

```
┌──────────────────────────────────────────────────┐
│ Library                                          │
├──────────────────────────────────────────────────┤
│                                                  │
│                                                  │
│              no ipas in your library             │
│                                                  │
│         finished downloads land here so          │
│         you can re-install without re-downloading│
│                                                  │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search   │ Download │  Library●│  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

### 7.2 已下载 — 按 App 分组

```
┌──────────────────────────────────────────────────┐
│ Library                              3 apps · 7 ipas│
├──────────────────────────────────────────────────┤
│                                                  │
│  ┌────┐ Telegram Messenger                  ▾   │
│  │ TG │ org.telegram.Telegraph                  │
│  └────┘                                          │
│                                                  │
│         ●─ 9.7.2  210 MB  installed             │
│         │   2026-04-30                          │
│         ●─ 9.7.0  205 MB  ipa only      install ›│
│         │   2026-04-02                          │
│         ●─ 9.5.4  198 MB  ipa only      install ›│
│             2026-01-12                          │
│                                                  │
│  ┌────┐ Discord                             ▾   │
│  │ DC │ com.hammerandchisel.discord              │
│  └────┘  ●─ 165.0  124 MB  installed            │
│                                                  │
│  ┌────┐ WeChat                              ▾   │
│  │ WX │ com.tencent.xin                          │
│  └────┘  ●─ 8.0.32  286 MB  installed           │
│             ●─ 8.0.30  280 MB  ipa only install ›│
│             ●─ 8.0.18  271 MB  ipa only install ›│
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search   │ Download │  Library●│  Settings   │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

`▾` = 展开/收起该 App 所有版本。

### 7.3 状态徽章

| 徽章 | 含义 |
|---|---|
| `installed` | 当前桌面上的版本（通过 `LSApplicationWorkspace` 反查 bundle id 一致 + 版本号一致） |
| `ipa only` | 本地存了 IPA，但桌面没装这一版（要么没装、要么装了别的版本） |
| `installed (other ver)` | 桌面装的是别的版本；混合状态 |

### 7.4 行操作

横划 row 暴露：

```
       ◀ swipe                            swipe ▶
                              [share][delete]
[install]
```

或长按弹同款 §6.4 menu。

---

## 8. Tab 5: Settings

### 8.1 主页

```
┌──────────────────────────────────────────────────┐
│ Settings                                         │
├──────────────────────────────────────────────────┤
│                                                  │
│  ACCOUNT                                         │
│  ┌────────────────────────────────────────────┐  │
│  │  ◉  evil0ctal_alt@icloud.com   stealth   ›│  │
│  │     storefront US · DSID 2113xx            │  │
│  ├────────────────────────────────────────────┤  │
│  │  ○  jp_alt@icloud.com          manual    ›│  │
│  │     storefront JP · last login 2026-04-12  │  │
│  ├────────────────────────────────────────────┤  │
│  │  +  Add manual account                     │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  DEVICE                                          │
│  ┌────────────────────────────────────────────┐  │
│  │  Device GUID            F3A1•••••EC72    ›│  │
│  ├────────────────────────────────────────────┤  │
│  │  Stealth diagnostics                     ›│  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  STORAGE                                         │
│  ┌────────────────────────────────────────────┐  │
│  │  Downloads folder        1.4 GB · 7 ipas  │  │
│  ├────────────────────────────────────────────┤  │
│  │  Clear cache                       12 MB  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ABOUT                                           │
│  ┌────────────────────────────────────────────┐  │
│  │  Version           0.5.0 (build 42)      ›│  │
│  ├────────────────────────────────────────────┤  │
│  │  Logs                                    ›│  │
│  ├────────────────────────────────────────────┤  │
│  │  License                    GPL-2.0 only │  │
│  ├────────────────────────────────────────────┤  │
│  │  Source                  github.com/...  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
├──┬───────────┬──────────┬──────────┬─────────────┤
│  │  Search   │ Download │  Library │ Settings ●  │
└──┴───────────┴──────────┴──────────┴─────────────┘
```

### 8.2 Account picker（多账号管理）

```
┌──────────────────────────────────────────────────┐
│ ← Settings                Choose account         │
├──────────────────────────────────────────────────┤
│                                                  │
│  STEALTH (1)                                     │
│  ┌────────────────────────────────────────────┐  │
│  │  ◉  evil0ctal_alt@icloud.com               │  │
│  │     storefront US · borrowed from system   │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  MANUAL (2)                                      │
│  ┌────────────────────────────────────────────┐  │
│  │  ○  jp_alt@icloud.com                      │  │
│  │     storefront JP · token 4d ago           │  │
│  ├────────────────────────────────────────────┤  │
│  │  ○  cn_alt@icloud.com                      │  │
│  │     storefront CN · token 11d ago ⚠        │  │
│  ├────────────────────────────────────────────┤  │
│  │  +  Add another                            │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  swipe to remove a manual account                │
│                                                  │
└──────────────────────────────────────────────────┘
```

`⚠` = token 即将过期（>7 天）；点击会触发 `rotatePasswordToken`。

### 8.3 Device GUID detail

```
┌──────────────────────────────────────────────────┐
│ ← Settings                Device GUID            │
├──────────────────────────────────────────────────┤
│                                                  │
│   ┌──────────────────────────────────────────┐   │
│   │   F3A1 4D8E 91C2 7B4F EC72              │   │
│   └──────────────────────────────────────────┘   │
│                                                  │
│   Treat this string as a password.               │
│   Apple ties it to your Apple ID; sharing it     │
│   exposes your session.                          │
│                                                  │
│   Source: borrowed from system (App Store)       │
│   First seen: 2026-04-12 19:33                   │
│                                                  │
│                                                  │
│   ┌────────┐  ┌──────────┐  ┌──────────────┐     │
│   │  copy  │  │  export  │  │  rotate ⚠    │     │
│   └────────┘  └──────────┘  └──────────────┘     │
│                                                  │
│   rotate is destructive and only applies to      │
│   manual mode. stealth GUID is system-owned and  │
│   cannot be rotated from this app.               │
│                                                  │
└──────────────────────────────────────────────────┘
```

`copy` 拷贝完整字符串到剪贴板（同时把日志的 GUID 字段降级到 `<guid>` 占位）；`export` 导出为单行 `.txt` 走 share sheet；`rotate` 仅 manual 可点，触发 `KeychainVault.remove + DeviceIdentifier.generateRandom`。

### 8.4 Stealth diagnostics（debug-only 入口）

仅 `#if DEBUG` 编译进 Settings；release 包看不到此入口。M0.5 PoC 阶段重度使用。

```
┌──────────────────────────────────────────────────┐
│ ← Settings                Stealth diagnostics    │
├──────────────────────────────────────────────────┤
│                                                  │
│  iOS 16.6.1 · iPhone 12 Pro                      │
│  TrollStore 2.0.12                               │
│  EvilStore 0.5.0 (42)                            │
│                                                  │
│  ─ Path A — accountsd ───────────────────────── │
│  ┌────────────────────────────────────────────┐  │
│  │  status       ok                           │  │
│  │  ent          .fullaccess granted          │  │
│  │  DSID         2113xxxxxxxx                 │  │
│  │  altDSID      0001-XXXX-XXXX-XXXX-XXXX     │  │
│  │  storefront   143441-19,29                 │  │
│  │  oauthToken   45 chars (redacted)          │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ─ Path B — filesystem ──────────────────────── │
│  ┌────────────────────────────────────────────┐  │
│  │  status       ok                           │  │
│  │  accountInfo  /var/.../accountInfo (4.1 KB)│  │
│  │  cookies      4 cookies from itunesstored  │  │
│  │  GUID         F3A1...EC72                  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ─ Path C — keychain ───────────────────────── │
│  ┌────────────────────────────────────────────┐  │
│  │  status       denied                       │  │
│  │  reason       access group not granted     │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ─ Path D — XPC storeaccountd ──────────────── │
│  ┌────────────────────────────────────────────┐  │
│  │  status       skipped                      │  │
│  │  reason       not implemented in v0.5      │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────┐  ┌──────────────────────────┐  │
│  │   re-run     │  │  export markdown report  │  │
│  └──────────────┘  └──────────────────────────┘  │
│                                                  │
│  exported reports redact tokens/cookies/DSID     │
│  tail-4 — safe to share for issue triage         │
│                                                  │
└──────────────────────────────────────────────────┘
```

### 8.5 Logs

```
┌──────────────────────────────────────────────────┐
│ ← Settings                  Logs                 │
├──────────────────────────────────────────────────┤
│                                                  │
│  filter: all  http  stealth  install  zip        │
│                                                  │
│  18:22:14  http      GET .../bag.xml  200 412B   │
│  18:22:14  stealth   path A: ok in 38ms          │
│  18:22:15  http      POST .../authenticate  200  │
│  18:22:18  http      POST .../volumeStore... 200 │
│  18:22:18  zip       inject 1 sinf + metadata    │
│  18:22:19  install   url scheme apple-magnifier  │
│  18:22:19  install   handed off to TrollStore    │
│                                                  │
│           tap row to expand · pull to refresh    │
│                                                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  │
│  │   clear    │  │   copy     │  │  share .txt│  │
│  └────────────┘  └────────────┘  └────────────┘  │
│                                                  │
└──────────────────────────────────────────────────┘
```

行点击展开完整 log；GUID/token/cookie/DSID 字段已被 `Logger.info(sanitize:)` 屏蔽（见 §5.12 of 2 号文档）。

### 8.6 About

```
┌──────────────────────────────────────────────────┐
│ ← Settings                  About                │
├──────────────────────────────────────────────────┤
│                                                  │
│            ┌──────────────┐                      │
│            │  EvilStore   │                      │
│            └──────────────┘                      │
│                                                  │
│              version  0.5.0                      │
│              build    42                         │
│              commit   abc1234                    │
│                                                  │
│                                                  │
│   GPL-2.0-only · 2026 Evil0ctal                  │
│                                                  │
│   built on top of                                │
│     ipatool (MIT) · majd                         │
│     TrollStore (MIT) · opa334                    │
│     ZIPFoundation (MIT) · weichsel               │
│                                                  │
│   not affiliated with Apple Inc.                 │
│                                                  │
│                                                  │
│         github.com/evil0ctal/EvilStore           │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 9. 全局 Modal / Alert

### 9.1 Install 确认

```
                ┌──────────────────────────────────┐
                │                                  │
                │     Install via TrollStore?      │
                │                                  │
                │   Telegram Messenger 9.7.2       │
                │   210 MB · org.telegram          │
                │                                  │
                │   TrollStore will take over for  │
                │   the actual install.            │
                │                                  │
                │  ┌─────────┐    ┌────────────┐   │
                │  │ cancel  │    │  install   │   │
                │  └─────────┘    └────────────┘   │
                │                                  │
                └──────────────────────────────────┘
```

### 9.2 TrollStore 错误码 — 模板

```
                ┌────────────────────────────────────┐
                │                                    │
                │   Install error  179               │
                │                                    │
                │   A system app already uses        │
                │   the bundle id                    │
                │                                    │
                │     com.apple.something            │
                │                                    │
                │   Forcing this would risk a        │
                │   bootloop. Try a different        │
                │   version of this app.             │
                │                                    │
                │  ┌──────────┐  ┌────────────────┐  │
                │  │ details  │  │     close      │  │
                │  └──────────┘  └────────────────┘  │
                │                                    │
                └────────────────────────────────────┘
```

`details` 弹完整 log（来自 `TSApplicationsManager.installIpa` 的 stdout/stderr）。错误码字典见 1 号文档 §1.2.3。

| 码 | 简短文案 | 操作建议 |
|---|---|---|
| 166–169 | "couldn't read the .ipa file" | retry / re-download |
| 171 | "another app uses this bundle id" | force install |
| 173 | "ldid is missing on this device" | install ldid first |
| 175 / 185 | "couldn't sign the binary" | report to issue tracker |
| 179 | "system app conflict" | bootloop risk — skip |
| 180 | "binary is encrypted" | wrong source — only decrypted ipas work |
| 182 | "developer mode required" | reboot + enable dev mode |
| 184 | "some plug-ins are still encrypted" | partial install — main app likely works |

### 9.3 passwordToken 过期（stealth 模式）

```
                ┌────────────────────────────────────┐
                │                                    │
                │   Session expired                  │
                │                                    │
                │   Apple's session token has        │
                │   rotated. Refresh it by going     │
                │   to Settings › Apple ID, sign     │
                │   out and back in once, then       │
                │   relaunch EvilStore.              │
                │                                    │
                │   We will pick up the new token    │
                │   automatically.                   │
                │                                    │
                │   ┌──────────────┐  ┌──────────┐   │
                │   │ open settings│  │  later   │   │
                │   └──────────────┘  └──────────┘   │
                │                                    │
                └────────────────────────────────────┘
```

`open settings` 通过 `UIApplication.open(URL("App-Prefs:APPLE_ACCOUNT"))` —— 这个 deeplink 在 iOS 14–17 都可用。

### 9.4 GUID copy 警告

剪贴板拷 GUID 时弹的 toast：

```
            ┌──────────────────────────────┐
            │  GUID copied to clipboard.   │
            │  Treat it like a password.   │
            └──────────────────────────────┘
```

3 秒自动消失；不阻塞操作。

### 9.5 Network unreachable

非 modal，是 RootView 顶部 banner：

```
┌──────────────────────────────────────────────────┐
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  ⚠  offline · cached data only        retry      │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
├──────────────────────────────────────────────────┤
│ Search                                       US ▾│
│  ...                                             │
```

---

## 10. 用户主流程图

### 10.1 冷启动到主界面

```
            ┌───────────┐
            │  launch   │
            └─────┬─────┘
                  │
            first launch?
                ┌─┴─┐
               yes  no
                │    │
                ▼    ▼
       ┌──────────┐ ┌────────────────┐
       │onboarding│ │ pick last-used │
       │  §2.1    │ │   account      │
       └────┬─────┘ └────────┬───────┘
            ▼                │
       ┌──────────┐          │
       │ stealth  │          │
       │  §2.2    │          │
       └────┬─────┘          │
            │                │
       any path ok?          │
         ┌─┴─┐               │
        yes  no              │
         │    │              │
         ▼    ▼              │
     ┌─────┐ ┌──────────┐    │
     │ ok  │ │ manual   │    │
     │§2.3 │ │ login §3 │    │
     └──┬──┘ └────┬─────┘    │
        │         │          │
        └────┬────┴──────────┘
             ▼
       ┌──────────┐
       │ RootView │
       │ (search) │
       └──────────┘
```

### 10.2 装上一个旧版

```
search "telegram"          §4.3
       │
       ▼
tap "Telegram Messenger"   §5
       │
       ▼
scroll to "9.5.4"          §5.2
       │
       ▼
tap → ● selected, Download appears
       │
       ▼
tap Download
       │
       ├── creates DownloadTask
       └── switches to Downloads tab
       │
       ▼
in-flight progress         §6.2
       │
       ├── purchase license (if needed)  ← background
       ├── HTTP GET .ipa with Range
       ├── IPAPatcher inject metadata + sinf
       ▼
queue row → done           §6.2
       │
       ▼
tap "install"
       │
       ▼
install confirm modal      §9.1
       │
       ▼
TrollStoreBridge.install() → apple-magnifier://install?url=...
       │
       ▼
TrollStore takes over (out of our process)
       │
       ▼
home screen icon appears   ← user verifies
```

### 10.3 Stealth 会话过期回路

```
user: tap Download
   │
   ▼
AppStoreClient.download
   │
   ▼
HTTP 200 but body has failureType=2034
   │
   ▼
DownloadService catches → SystemSessionImporter.snapshot() retry
   │
   ▼
new snapshot still has stale token (Apple hasn't refreshed)
   │
   ▼
DownloadService → UI: §9.3 "Session expired" modal
   │
   ▼
user taps "open settings"
   │
   ▼
App-Prefs:APPLE_ACCOUNT
   │
   ▼
user signs out + in (Apple rotates token in storeaccountd)
   │
   ▼
user back in EvilStore
   │
   ▼
on .didBecomeActive → SystemSessionImporter.snapshot() refresh
   │
   ▼
DownloadService.retryEnqueued()
   │
   ▼
download proceeds
```

---

## 11. 视觉规范

### 11.1 颜色（暗色主导）

```
background        #0A0A0C   nearly-black, not pure
surface           #18181B   cards / list rows
surface-elev      #27272A   pressed / selected rows
border            #3F3F46
text-primary      #FAFAFA
text-secondary    #A1A1AA
text-tertiary     #71717A
accent            #FF3B30   Apple system red — destructive + brand
accent-success    #30D158
accent-warning    #FFD60A
accent-info       #0A84FF
```

亮色（M5 才支持）：直接用 `Color(.systemBackground)` 等系统色，不自定义。

### 11.2 字号阶梯

| 用途 | 字号 / 字重 |
|---|---|
| Title (nav) | 17 semibold |
| Large title (Settings 顶层) | 28 bold |
| Section header | 13 medium uppercase tracking +0.5 |
| Body | 16 regular |
| Body emphasized | 16 semibold |
| Footnote | 13 regular |
| Caption (timestamps, ext id) | 12 regular monospaced |

ext id 用 `.monospacedDigit()`，方便对齐。

### 11.3 间距

8pt grid。常用：

- 行内 padding：12 or 16
- 卡片 padding：16
- 卡片间隔：12
- Section 间隔：24

### 11.4 圆角

- 列表行 / 卡片：12
- 按钮：10
- 头像 / icon：8
- Modal：14（系统默认）

### 11.5 SF Symbols 清单（M0–M5 用到的）

```
magnifyingglass       Search
arrow.down.circle     Downloads tab
square.stack          Library tab
gear                  Settings tab
xmark                 close / cancel
xmark.circle.fill     clear text
chevron.right         disclosure
chevron.down          expand
checkmark             ok / done
exclamationmark.triangle  warning
exclamationmark.circle    error
ellipsis              menu
ellipsis.circle       row menu
square.and.arrow.up   share
trash                 delete
arrow.clockwise       retry
pause / play          download control
plus.circle           add
doc.on.doc            copy
arrow.down.doc        export
network               offline banner
key.fill              GUID
person.crop.circle    account
```

`SF Symbols 1.x` 在 iOS 13+ 已可用，全部线框使用的图标都不超过 1.x。

---

## 12. 无障碍

- **VoiceOver**：每个 row 有 `accessibilityLabel = "<App name>, version <ver>, <state>"`，combinable。
- **Dynamic Type**：全文用 `.font(.body)` 等系统语义字号；自定义字号必须 `relativeTo:` 系统语义。
- **Reduce Motion**：进度条改成静态文本 "downloading 68%"，不做条带动画。
- **High Contrast**：边框宽 1px → 2px；text-secondary 提一档。
- **触摸目标**：最小 44×44pt（Apple HIG）；行高严格 ≥ 56pt。

---

## 13. 文案语言策略

- 源串：**English**（参 §0.8、2 号文档 §7.7）。
- 必备 localization：`en` + `zh-Hans`。`Localizable.xcstrings`，M1 起跟代码同步建立。
- **不**用机翻；zh-Hans 由项目所有者人工审一次。
- 错误码文案：英文 + 必要时附 storefront 原 `customerMessage` 的 raw 文本（折叠在 `details`）。

不允许的措辞（直接拒）：
- "Oops!" / "Whoops!" / "Sorry,"
- "Something went wrong"（必须给具体错误码）
- emoji 在主文案里（仅图标位置可以是 SF Symbol）
- "We" / "Our team" / "Don't worry"
- 中文文案里的"亲"、"哦~"、"啦"

---

## 14. 待办与开放问题

| # | 项 | 决策 |
|---|---|---|
| 14.1 | iPad 适配（split view）做不做？ | M5 之后再说，v1 仅 iPhone 体验打磨好 |
| 14.2 | 深链 `evilstore://app/<bundleid>` 直跳 detail 要不要做？ | M4 顺手做 |
| 14.3 | macOS Catalyst 端口？ | 不做，重叠 Asspp 没必要 |
| 14.4 | 主屏小组件（widget）展示队列？ | 不做，越权能力被 Apple 收紧 |
| 14.5 | iOS 14 SwiftUI 预览能不能在 Xcode canvas 里跑？ | 测了再说，能跑当然用；不能就 device-only |
| 14.6 | Detail 页要不要展示 changelog（Apple "What's New"）？ | M5 加，从 iTunes Lookup 的 `releaseNotes` 取 |
| 14.7 | App icon 设计（不能用 Apple 默认） | 单独开 issue，找 designer |

---

> **审查重点**：
> 1. §1 IA 总图 + Tab 顺序 — 是否漏页面 / 是否多 tab？
> 2. §2 Onboarding 三步 — 风控提示文案够不够？要不要加"建议先在系统设置登录 App Store"？
> 3. §5 App Detail 时间轴 — 信息密度合适吗？要不要把 ext id 默认折叠？
> 4. §6 Downloads 队列 — 三段式（in flight / done / failed）是否清晰？
> 5. §8 Settings — 入口数量合适吗？还要加什么（如"导入/导出账号"、"切换协议端点"）？
> 6. §9 错误码 modal 模板 — 措辞 OK 吗？
> 7. §11 暗色配色 — 接受 hex 还是改用 SwiftUI semantic color？
> 8. §13 不允许措辞清单 — 还想 ban 什么？
> 9. §14 14.1 / 14.2 / 14.7 这几个未决项 — 现在拍板还是留到后续？
>
> 全部 OK 后开工 M0。
