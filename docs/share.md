# Share kit

Copy-paste material for announcing DialPilot. Nothing here is required to use the app — it exists so every post says the same true things.

Rules of thumb:

- Lead with the **problem** (a dial plus coding agents), not the feature list.
- Always say **unofficial, MIT, not affiliated with Ulanzi**. The project depends on that honesty.
- Link the repo, not a download. There is no notarized binary; people build locally.
- Don't claim more than the README does. If a platform asks for a screenshot, use the ones in `docs/images/`.
- Chinese and English audiences get different framing: Chinese posts can lean on the VibeKey/优篮子 context; English posts should explain what an AU05 is in one clause.

---

## 1. GitHub repository metadata

**About (short description, ≤ 160 chars)**

> macOS companion for the Ulanzi AU05 (VibeKey) dial: seven custom bindings plus live coding-agent status on the device LEDs. MIT, unofficial.

**Topics**

```
macos swift menu-bar hid ulanzi vibekey dial coding-agents claude-code codex
macos-app appkit iokit automation hardware status-light
```

**Website**: leave empty (no landing page). **Releases**: attach the signed `.zip` if you ship one.

**Social preview text** (for the repo card / OG description)

> One dial, seven bindings, and your agents' status on a physical light. DialPilot is a small macOS menu-bar app for the Ulanzi AU05.

---

## 2. Elevator pitches

**One line**

> A macOS menu-bar app that turns a $40 Ulanzi dial into a controller and status light for coding agents.

**Short (2 sentences)**

> The Ulanzi AU05 is a USB knob with three buttons and four LEDs. DialPilot binds all seven controls to whatever you want, and drives the LEDs from Claude Code / Codex / Qoder / WorkBuddy events so you can see "working", "done" and "needs approval" without looking at a terminal.

**Long (paragraph)**

> DialPilot is an unofficial macOS companion for the Ulanzi AU05 (sold as VibeKey): a USB dial with three buttons and four indicator LEDs. It gives every control a binding — presets or recorded keyboard shortcuts — and writes them back to the device's own six slots, so the keys keep working after the app quits. The part that makes it more than a macro pad is the light pipeline: hooks from seven coding agents feed a multi-session arbiter, and the LEDs show the highest-priority state (approval > error > compaction > thinking > working > done). It is a menu-bar app, zero dependencies, no network, MIT.

---

## 3. X / Twitter

**Single post**

> I use a tiny USB dial as a controller for coding agents.
>
> DialPilot: 7 bindings on the Ulanzi AU05, plus its 4 LEDs show what Claude Code / Codex / Qoder are doing — thinking, working, done, needs approval.
>
> Menu-bar app, no dependencies, MIT.
> github.com/lichengwu/dialpilot

**Thread (4 posts)**

1. The AU05 is a $40 USB knob with 3 buttons and 4 LEDs, sold as VibeKey. Nice hardware, mediocre software. So I wrote a macOS companion for it: DialPilot.
2. Every control is bindable — presets or recorded chords (up to 4 keys, left/right modifiers distinguished). Bindings are written back to the device's six slots, so the keys survive quitting the app.
3. The interesting half is the lights. Hooks from Claude Code, Codex, Qoder, WorkBuddy and others feed a session arbiter; the LEDs show the highest-priority state. Approval request wins over everything.
4. Menu-bar only, zero dependencies, no network, bilingual UI (EN/中文), MIT. Unofficial — not affiliated with Ulanzi. github.com/lichengwu/dialpilot

---

## 4. Show HN

**Title**

> Show HN: DialPilot – a macOS companion for a USB dial that shows agent status

**First comment (post it yourself, immediately)**

> Author here. The Ulanzi AU05 (VibeKey) is a USB HID dial: rotary knob, three buttons, a voice key and four LEDs. The vendor app is a macro configurator; it does not know anything about coding agents.
>
> DialPilot does two things. First, it binds all seven controls and writes them to the device's own six stored slots, so the keys keep working with the app closed. Second, it listens to agent hooks (Claude Code, Qwen Code, Qoder, WorkBuddy, Codex, DeepSeek Harness, QwenWork) and renders the highest-priority state on the LEDs — approval request beats error beats compaction beats thinking beats working beats done.
>
> Things that were harder than expected:
> - The device keeps its USB interface alive when the knob is switched off, and ACKs heartbeats. "Enumerated" is not "working". Liveness is decided by whether power queries are answered.
> - The menu-bar panel used to be an NSPopover. With Bartender/Ice moving the status item, the popover was handed an off-screen anchor and opened as a giant blank rectangle. It is now a borderless NSPanel with pure-function geometry and unit tests.
> - Multi-session arbitration needs deterministic tie-breaking, otherwise the LEDs flicker between two equally-old sessions.
>
> Swift, AppKit + IOKit, zero third-party dependencies, MIT. No vendor binaries are included or linked; protocol notes are in docs/protocol.md.
>
> Happy to answer anything about HID, AppKit panel geometry, or agent hook contracts.

---

## 5. Reddit (r/macapps, r/macsetups)

**Title**

> DialPilot – a menu-bar app for the Ulanzi AU05 dial, with agent status on its LEDs

**Body**

> Picked up an Ulanzi AU05 (a small USB knob with 3 buttons and 4 LEDs, sold as VibeKey) and the official software only does macros. I wanted two things: my own bindings, and a physical "is my agent done / waiting for approval" light.
>
> So: seven bindable controls (presets or recorded shortcuts, written back to the device so they survive quitting the app), plus a light pipeline fed by hooks from Claude Code, Codex, Qoder, WorkBuddy etc. Multiple sessions are arbitrated by priority, so the LEDs never flicker between two agents.
>
> It's a menu-bar app, no dependencies, no network, EN/中文 UI, MIT. Unofficial, not affiliated with Ulanzi — you build it locally with Xcode CLT.
>
> Repo + screenshots: github.com/lichengwu/dialpilot

---

## 6. 中文平台

### 即刻 / 朋友圈（短）

> 把一颗 40 刀的 USB 旋钮，变成了 coding agent 的状态灯。
>
> DialPilot：Ulanzi AU05 七个控制全部可自定义，四颗 LED 实时显示 Claude Code / Codex / Qoder / WorkBuddy 在干嘛——思考、干活、完成、等你审批。
>
> 菜单栏 App，零依赖，不联网，MIT，中英双语。非官方，与优篮子无关。
> github.com/lichengwu/dialpilot

### V2EX（macOS 节点）

**标题**：分享一个把 Ulanzi AU05 旋钮做成 Agent 状态灯的 macOS App

**正文**：

> 手上有个 Ulanzi AU05（商品名 VibeKey），USB 旋钮 + 三按键 + 四颗灯。官方软件只能配宏，跟 coding agent 完全没关系，就自己写了个菜单栏 App。
>
> 两件事：
> 1. 七个控制全部可绑定（预设动作或录制组合键），并且写回设备自带的六格存储——App 退出后按键照样生效。
> 2. 接 Agent 的 hooks（Claude Code、Qwen Code、Qoder、WorkBuddy、Codex、DSH、千问办公），多会话按优先级仲裁后驱动四颗灯：要审批 > 出错 > 压缩 > 思考 > 干活 > 完成。
>
> 踩过的两个坑写在这里，可能对做 macOS 的人有用：
> - 设备关机后 USB 还在、心跳还回，但固件不应答。所以"设备在"不等于"能用"，只能拿电源查询的往返判活。
> - 菜单栏面板原来是 NSPopover，用 Bartender/Ice 挪图标时它会拿到屏幕外的锚点，弹出一大片空白。现在改成自持的无边框 NSPanel，几何是纯函数 + 单测。
>
> Swift + AppKit/IOKit，零第三方依赖，不联网，MIT。非官方实现，与优篮子无关；不含任何厂商二进制。
> github.com/lichengwu/dialpilot

### 少数派（文章开头）

> **把 Agent 的状态搬到桌面上：一个旋钮的改造记录**
>
> 屏幕里的 Agent 越来越多，但"它现在到底在干嘛"仍然要切窗口才能知道。这篇文章讲的是怎么用一颗 USB 旋钮 + 四颗 LED，把思考、干活、完成、待审批这几种状态变成余光可见的物理信号；以及为了让这件事稳定，踩过的 HID、菜单栏窗口和多会话仲裁的坑。

### 小红书（口语化）

> 把桌面旋钮变成 AI 打工进度灯 💡
>
> 设备是 Ulanzi AU05（VibeKey），本来只能当宏键盘。写了个 Mac 小工具 DialPilot：
> · 旋钮 + 三个键全部自己定义
> · 四颗灯显示 Claude Code / Codex 在思考、干活、还是等你点同意
> · 菜单栏常驻，不联网，免费开源
>
> 最爽的是"等审批"那档：中键+下键快闪，余光一扫就知道该回去了。
> 非官方，自己用 Xcode 编译，搜 github dialpilot 就有。

---

## 7. Asset checklist

Before posting, make sure the repo has:

- [ ] `docs/images/panel-preview.png` — the panel at 2× (hero shot)
- [ ] `docs/images/panel-hover-detail.png` — chart hover detail
- [ ] `docs/images/guide-window-preview.png` — full-screen light guide
- [ ] `docs/images/hooks-window.png` — agent connection list
- [ ] `docs/images/appicon-preview.png` — icon
- [ ] README badges render (tests count matches the suite)
- [ ] GitHub social preview uploaded (1280×640; use the panel shot on a dark background)

## 8. Claims to avoid

- ❌ "Works with any dial" — it is device-bound to VID `0xFFF1` / PID `0x00DD`.
- ❌ "Plug and play" — two permissions and a signed build are required; say so.
- ❌ "Supports Windows/Linux" — macOS 13+ only.
- ❌ "Official" / "Ulanzi-approved" — it is not.
- ❌ Any promise about firmware compatibility. Device writes are at the user's risk, mitigated by verified command groups and read-back.
