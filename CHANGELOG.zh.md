# 更新日志

本文件记录 DialPilot 的所有重要变更。格式参考
[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循
[语义化版本](https://semver.org/lang/zh-CN/)。

English: [CHANGELOG.md](CHANGELOG.md)

## [1.1.4] — 2026-11-23

「插着却显示未连接」版本。Ulanzi Studio 运行时独占旋钮、DialPilot 主动让位——
这本身是设计；坏的是 Studio 退出后 DialPilot 不一定接得回来，而且面板没给
用户任何可操作的入口。

### 修复

- **Studio 退出后自动接回。** 原实现只依赖
  `NSWorkspace.didTerminateApplicationNotification`，而这个通知 macOS 可能
  不投递（2026-11-23 复现：Studio 已退出、无回调、监听一直停着直到重启 App）。
  现在交接由每次 UI 刷新时的存在状态差分（`DialVendorPresence`）+ 30 秒
  维护轮询驱动；系统通知只作为快路径保留。

### 新增

- **「退出 Ulanzi Studio」横幅按钮。** Studio 运行时面板显示与权限横幅同级的
  橙色横幅，一键退出（先优雅退出，4 秒不退强制——与写入设备路径同一策略）。
  退出后 DialPilot 自动接回。
- `DialVendorPresence`（Core，5 条测试）与中英双语横幅布局/溢出回归测试
  （App，1 条）。测试总数 277（Core 252 + App 25）。

### 变更

- README ×2 与用户指南 ×2 写清三种「用不了」（两项权限 + Studio），并建议
  把 Ulanzi Studio 从登录项移除——这是开机后「未连接」最常见的原因。

## [1.1.3] — 2026-11-22

文档与发版工具版本，App 行为无变化。但它带着**新的 ad-hoc 签名身份**，所以升级
会让「输入监控」和「辅助使用」授权失效一次——这一版正是把原因写清楚的那版，
解法是把两个开关都关掉再打开，然后重启 App。

### 新增

- **`scripts/release.sh`**：一条命令走完发版——前置检查（工作区干净、在 `main`、
  tag 未被占用、CHANGELOG 有对应段落、`gh` 已登录）、升版本号、跑测试、打 DMG、
  提交打 tag 推送、创建 GitHub Release（发布说明直接从 CHANGELOG 该段落抽取）、
  最后更新 cask。`--dry-run` 只打印计划，不动任何文件。

### 变更

- **权限文档讲清了升级到底发生了什么。** TCC 的一条授权 = bundle ID **加上**
  代码签名要求；ad-hoc 签名的要求只有 `cdhash H"…"` 一条，所以每个版本都是新身份。
  系统设置仍按 bundle ID 列出条目、开关仍显示为开——「开关是开的却没权限」因此
  是同一个现象的两面，不是两个问题。解法（关掉再打开，然后重启 App）以及用
  `sqlite3` + `csreq` 查 macOS 到底记了什么的配方，已写进用户指南、README 与
  cask 的 caveats。
- **用户指南点明 `brew upgrade` 本质是重装**（Homebrew 先卸旧 artifacts、再装新的），
  所以升级必然换 cdhash。

## [1.1.2] — 2026-11-22

安装通道版本：两条完全不碰 Gatekeeper 的安装路径、不会过期的发布映像，以及
对「仍然会弹窗」那条路径的正确说明。

### 新增

- **Homebrew cask**（`lichengwu/homebrew-tap`，见 README）：锁死映像 SHA-256，
  装完清除隔离标记，`brew install --cask lichengwu/tap/dialpilot` 装好即可双击运行。
- **`scripts/install.sh`**：解析最新版本、用发布页校验和验证、装到
  `/Applications`、清隔离标记。面向不用 Homebrew 的人。
- **`.sha256` 资产**：每个 DMG 旁边一起发布；两条安装通道与 cask 都据此校验。
- **`scripts/update-cask.sh`**：发布后把新版本号与校验和写进 tap；cask 结构漂移
  时直接拒绝改动。

### 修复

- **macOS 15+ 的 Gatekeeper 说明是错的。** 1.1.1 写的是「右键 → 打开」，而 Apple
  在 Sequoia 已移除该绕过方式（macOS 26 同样）。现在写的正确路径是：先触发一次
  被拦的启动，再到「系统设置 → 隐私与安全性 → 仍要打开」，且该按钮只在约一小时
  内可见。

### 变更

- **发布映像改用 ad-hoc 签名**，不再用 Apple Development 证书。对浏览器下载来说
  两者都过不了 Gatekeeper，但没打时间戳的 Apple Development 签名在证书过期后会
  验证失败——那会让所有旧版本变成「App 已损坏」。ad-hoc 没有证书链，永不过期。
  `build-app.sh` 仍用 Apple Development 给你本地那份签名，因为稳定的签名才能保住
  已授予的权限。

## [1.1.1] — 2026-11-22

分发版本：DialPilot 现在以磁盘映像形式提供下载，用起来不再需要编译工具链。

### 新增

- **DMG 安装包**（`scripts/make-dmg.sh`）——构建 `DialPilot.app`，连同
  `/Applications` 快捷方式一起打成已签名的 zlib 压缩映像，产物在
  `dist/DialPilot-<version>.dmg`。每个 release 都会附上这个文件。

### 变更

- 安装文档改成下载优先；从源码编译降为「想读代码或改代码」的路径。
- 文档里写明唯一的 Gatekeeper 步骤：App 用 Apple Development 证书签名、
  **未做公证**，首次启动需要右键 → 打开（或「系统设置 → 隐私与安全性 →
  仍要打开」）。

### 移除

- 分享文案草稿（`docs/share.md`、`docs/share.zh.md`）——版本说明改由本文件
  与 GitHub Releases 页面承载。

## [1.1.0] — 2026-11-21

「消失在菜单栏里」版本：面板自己管窗口，设备状态不再说谎，界面中英双语。

### 新增

- **菜单栏状态徽章**，固定优先级：设备不在/已关机 → 缺权限 → 低电量 →
  充电中 → 正常。一切正常时不显示任何徽章（`DialStatusBar`）。
- **电量环形仪表** 与 iStat 风格统计卡：今日 / 累计次数、最常用控制、
  7 天柱状图（每根柱子带数值，悬停显示完整日期、次数与当天最常用控制）。
- **本地使用统计**（`usage.json`，保留 90 天日明细，累计值永久保留；
  不联网、不含标识）。
- **全屏灯效图解**（Raycast 风格）：每种 Agent 状态一张卡片，←/→ 或横向
  滑动翻页，点击或 Esc 关闭。
- **设备存活判定**：关机的 AU05 仍挂在 USB 上并回心跳；连续两次电源查询
  无应答即显示「已连接 · 未响应」，同时清空旧电量（`DialDeviceLiveness`）。
- **权限横幅**：一键直达对应的系统设置面板。
- **中英双语界面**：类型化 key 表，跟随系统语言。
- **应用图标**（`AppIcon.icns`）。
- 新增 21 个测试，**共 271 个**（Core 247 + App 24），覆盖面板几何、状态
  徽章、存活判定、使用统计、本地化、面板布局与快照。

### 变更

- 面板由 `NSPopover` 改为自持有的无边框 `NSPanel`（`DialPanelController`）。
  窗口尺寸恒等于「内容 + 箭头」，由纯函数 `DialPanelGeometry` 计算。
- 面板宽度固定 380pt；动态文案一律截断，不再把窗口撑宽。
- 单组按键配置：AI/System 双组与 `switchProfile` 动作移除，旧配置启动时迁移。
- 设备备份全自动（改绑定防抖写入、连接后补写、首次启动写入），无写入按钮。
- 电源轮询随可见性调整：面板打开时每 3 个心跳，关闭时每 30 个，设备静默时每 8 个。
- `build-app.sh` 自动使用本机第一张 **Apple Development** 证书签名，重建不再
  让 TCC 授权失效；仅在没有任何证书时回退 ad-hoc。

### 修复

- 菜单栏管理工具（Bartender / Ice）移动或隐藏图标后，面板弹出为一大片空白
  ——旧 popover 拿到了屏幕外的锚点。
- 权限开关「打开了却没效果」：ad-hoc 签名每次构建都换身份，授权被静默作废。
- 插上充电器后状态不更新（设备不推送电源事件，只能主动查询）。
- 统计图悬停永远命中最后一列（`NSTrackingArea.inVisibleRect` 覆盖了分列矩形）。
- 低频用户的历史日数据永不清理；保留策略改为日历窗口。
- 退出时最后两秒的使用事件丢失。
- 图解窗口点击卡片区域无法关闭。
- 灯效卡在 380pt 下把状态标签挤成「Wo…」、并裁掉 Connect 按钮；改为三行，
  状态标签不再可压缩。
- 自绘仪表对 VoiceOver 不可见。

### 移除

- 双组切换、长按动作、面板内可折叠的灯效图解条。

## [1.0.0] — 2026-11-21

首个公开版本：Ulanzi AU05 七键自定义、多会话仲裁的 Agent 状态灯、七家
Agent 的 hooks 接入、零第三方依赖。
