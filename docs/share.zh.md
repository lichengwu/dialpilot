# 分享文案

用于发布 / 转发 DialPilot 的可直接粘贴素材。不用它们也能用 App——它们的作用是让每次对外表述都不夸大、不遗漏必要声明。

几条原则：

- 先讲**问题**（旋钮 + 一堆 Agent），再讲功能。
- 每次都注明**非官方、MIT、与优篮子无关**。这个项目靠这份诚实立足。
- 给仓库链接，不给二进制。没有公证签名包，大家自己本地构建。
- 不要比 README 说得更多。要配图就用 `docs/images/` 里的现成截图。
- 中英文语境不同：中文可以借 VibeKey / 优篮子的认知；英文要先用一句话解释 AU05 是什么。

---

## 1. 仓库元信息

**About（一句话简介，≤ 160 字符）**

> Ulanzi AU05（VibeKey）旋钮的 macOS 伴侣：七个自定义绑定，四颗 LED 实时显示 coding agent 状态。MIT，非官方。

**Topics**

```
macos swift menu-bar hid ulanzi vibekey dial coding-agents claude-code codex
macos-app appkit iokit automation hardware status-light
```

**Website**：留空（没有落地页）。**Releases**：有签名 zip 就挂上去。

**社交预览文案（仓库卡片 / OG 描述）**

> 一颗旋钮，七个绑定，加上 Agent 的实时状态灯。DialPilot 是给 Ulanzi AU05 写的 macOS 菜单栏小工具。

---

## 2. 电梯陈述

**一句话**

> 一个 macOS 菜单栏 App，把四十刀的 USB 旋钮变成 coding agent 的控制器和状态灯。

**两句话**

> Ulanzi AU05 是带三个按键、四颗 LED 的 USB 旋钮。DialPilot 把七个控制全部做成可自定义绑定，并用 Claude Code / Codex / Qoder / WorkBuddy 的事件驱动 LED——不用切窗口就知道它在思考、干活、完成，还是在等你审批。

**一段话**

> DialPilot 是 Ulanzi AU05（商品名 VibeKey）的非官方 macOS 伴侣。它给每个控制一个绑定（预设动作或录制的组合键），并写回设备自带的六格存储，所以 App 退出后按键照样生效。真正让它不只是宏键盘的是灯：七家 coding agent 的 hooks 汇入一个多会话仲裁器，四颗 LED 只显示最高优先级的状态（要审批 > 出错 > 压缩 > 思考 > 干活 > 完成）。菜单栏常驻，零第三方依赖，不联网，MIT。

---

## 3. 微信朋友圈 / 群

> 把一颗 40 刀的 USB 旋钮，变成了 coding agent 的状态灯。
>
> DialPilot：Ulanzi AU05 七个控制全部可自定义，四颗 LED 实时显示 Claude Code / Codex / Qoder / WorkBuddy 在干嘛——思考、干活、完成、等你审批。
>
> 菜单栏 App，零依赖，不联网，MIT，中英双语。非官方，与优篮子无关。
> github.com/lichengwu/dialpilot

---

## 4. 即刻

> 屏幕里的 Agent 越来越多，但"它现在在干嘛"还是得切窗口看。
>
> 于是把桌上那颗 Ulanzi AU05 旋钮改成了状态灯：思考慢闪、干活常亮、完成亮中键、要审批中+下快闪。余光一扫就知道该不该回去点同意。
>
> 顺手把七个控制全做成可绑定，写回设备，App 关了也能用。
> macOS 菜单栏 App，零依赖，不联网，开源。
> github.com/lichengwu/dialpilot

---

## 5. V2EX（macOS 节点）

**标题**：分享一个把 Ulanzi AU05 旋钮做成 Agent 状态灯的 macOS App

**正文**：

> 手上有个 Ulanzi AU05（商品名 VibeKey），USB 旋钮 + 三按键 + 四颗灯。官方软件只能配宏，跟 coding agent 完全没关系，就自己写了个菜单栏 App。
>
> 两件事：
>
> 1. 七个控制全部可绑定（预设动作或录制组合键），并且写回设备自带的六格存储——App 退出后按键照样生效。
> 2. 接 Agent 的 hooks（Claude Code、Qwen Code、Qoder、WorkBuddy、Codex、DSH、千问办公），多会话按优先级仲裁后驱动四颗灯：要审批 > 出错 > 压缩 > 思考 > 干活 > 完成。
>
> 踩过的两个坑，可能对做 macOS 的人有用：
>
> - 设备关机后 USB 还在、心跳还回，但固件不应答。所以「设备在」不等于「能用」，只能拿电源查询的往返判活。
> - 菜单栏面板原来是 NSPopover，用 Bartender / Ice 挪图标时它会拿到屏幕外的锚点，弹出一大片空白。现在改成自持的无边框 NSPanel，几何是纯函数 + 单测。
>
> Swift + AppKit/IOKit，零第三方依赖，不联网，MIT。非官方实现，与优篮子无关；不含任何厂商二进制。
> github.com/lichengwu/dialpilot

---

## 6. 少数派（文章开头）

> **把 Agent 的状态搬到桌面上：一颗旋钮的改造记录**
>
> 屏幕里的 Agent 越来越多，但「它现在到底在干嘛」仍然要切窗口才能知道。这篇文章讲的是怎么用一颗 USB 旋钮加四颗 LED，把思考、干活、完成、待审批这几种状态变成余光可见的物理信号；以及为了让这件事稳定，踩过的 HID、菜单栏窗口和多会话仲裁的坑。

---

## 7. 小红书

> 把桌面旋钮变成 AI 打工进度灯 💡
>
> 设备是 Ulanzi AU05（VibeKey），本来只能当宏键盘。写了个 Mac 小工具 DialPilot：
>
> · 旋钮 + 三个键全部自己定义
> · 四颗灯显示 Claude Code / Codex 在思考、干活、还是等你点同意
> · 菜单栏常驻，不联网，免费开源
>
> 最爽的是「等审批」那档：中键 + 下键快闪，余光一扫就知道该回去了。
> 非官方，自己用 Xcode 编译，搜 github dialpilot 就有。

---

## 8. 发布前素材清单

- [ ] `docs/images/panel-preview.png` —— 面板 2×（主图）
- [ ] `docs/images/panel-hover-detail.png` —— 统计悬停详情
- [ ] `docs/images/guide-window-preview.png` —— 全屏灯效图解
- [ ] `docs/images/hooks-window.png` —— Agent 接入列表
- [ ] `docs/images/appicon-preview.png` —— 图标
- [ ] README 徽章能正常渲染（测试数与实际一致）
- [ ] 已上传 GitHub 社交预览图（1280×640，深色底 + 面板截图）

## 9. 不要说的话

- ❌ 「支持任意旋钮」——设备绑定 VID `0xFFF1` / PID `0x00DD`。
- ❌ 「即插即用」——需要两项权限和签名构建，要如实说明。
- ❌ 「支持 Windows / Linux」——只支持 macOS 13+。
- ❌ 「官方」「优篮子认证」——都不是。
- ❌ 任何固件兼容性承诺。设备写入风险自担，缓解手段是只写已验证命令组 + 读回校验。
