# DialPilot 用户指南

> 配套阅读：README（功能与安装概览）、[protocol.md](protocol.md)（协议与逆向笔记）、[led-design.md](led-design.md)（灯效设计）。
> 目标：不看代码也能完成安装、配置、验收与排障。英文版见 [user-guide.en.md](user-guide.en.md)。

## 1. 安装与升级

### 首次安装

1. 完全退出 Ulanzi Studio（两个宿主会抢设备）。
2. 构建并签名：

   ```sh
   ./build-app.sh
   # 或指定证书：
   DIALPILOT_SIGNING_IDENTITY="Apple Development: 你的名字 (TEAMID)" ./build-app.sh
   ```

   脚本会自动挑选本机第一张 Apple Development 证书；没有任何证书时才回退 ad-hoc。
   **ad-hoc 签名每次重编都会换身份**，macOS 会把之前给的「输入监控 / 辅助使用」授权判为失效。
3. 产物在 `.build/app/DialPilot.app`（内含 `Contents/MacOS/dialpilotctl`），复制到 `/Applications/` 后启动。
4. 系统设置 → 隐私与安全性 → 打开「输入监控」和「辅助使用」。
5. 首次启动会自动迁移旧版 VibeKey Lite 的配置（若有）。

### 替换升级

**走 brew 安装的分发包（ad-hoc 签名）——授权必然失效一次**

```sh
brew update
brew upgrade --cask dialpilot      # 没有新版会直接告诉你
```

`brew upgrade` 对 cask 的实现是「先卸旧、再装新」（Homebrew 源码里走的是 `reinstall: true` + `uninstall(successor:)`），跟手工删掉 App 再装一次等价。而分发版是 ad-hoc 签名，它的代码签名要求只有 `cdhash H"…"` 一条——**新版本二进制不同，cdhash 必然不同，旧授权必然不匹配**。

所以升级后请做一次：

1. 系统设置 → 隐私与安全性 → **输入监控** → 把 DialPilot **关掉再打开**；
2. 同样的动作做一遍 **辅助使用**；
3. 退出并重新打开 DialPilot。

第 1、2 步的「关掉再打开」是必须的：开关本来就是开的时候，光看它亮着没用，只有 toggle 一次才会把新的签名要求写进 TCC。详见 §10 的「开关是开的但权限无效」。

**自己构建的版本（同一张证书）——授权沿用**

```sh
osascript -e 'tell application "DialPilot" to quit'
ditto ".build/app/DialPilot.app" "/Applications/DialPilot.app"
codesign --verify --strict "/Applications/DialPilot.app"
open "/Applications/DialPilot.app"
```

同一张证书签名 → 授权沿用，无需重新勾选。替换后 `dialpilotctl status` 应返回 `state=idle`。**注意不要把 ad-hoc 构建和证书构建混着装**，两者身份不通用，同样会失效一次。

## 2. 首次使用前（一次性，用 Ulanzi Studio 完成）

DialPilot 直接通过 HID 与设备通信，**不需要 Ulanzi Studio 运行**，但全新 AU05 建议先做一次：

1. 装好 Ulanzi Studio，USB 连接 AU05。
2. 若有固件更新，先升级。DialPilot 从不碰固件——只写已验证的灯控组和六格按键。
3. 在 Studio 里确认旋钮与三个按键的原生动作正常（验证硬件，拿到已知基线）。
4. 完全退出 Studio（⌘Q，关窗口不算），之后保持关闭。

不需要在 Studio 里绑定账号或配置按键——DialPilot 首次启动会自动写入自己的六格备份。

## 3. 面板说明

点菜单栏图标打开面板。宽度固定 380pt，高度随内容自适应；卡片从上到下：

| 区域 | 内容 |
| --- | --- |
| 设备卡 | 电量环（大数字 + 百分比）、连接/权限/响应状态、当前亮灯的 Agent 会话来由 |
| 按键卡 | 七个控制各一个下拉：预设动作或「录制键盘按键…」 |
| 灯效卡 | 全开 / 关闭 / 智能、实时状态 chip、预览下拉、接入 Agent、灯效图解入口 |
| 统计卡 | 今日 / 累计次数、最常用控制、7 天柱状图（首次使用前整卡隐藏） |
| 底部 | 唯一的维护按钮「退出」 |

关闭方式：**Esc**、**点面板外任意位置**、**⌘-Tab 切走**。

关于位置：面板不是系统 popover，而是 App 自己定位的窗口。用 Bartender / Ice 这类工具挪动或隐藏菜单栏图标时，面板会跟着图标的实时位置移动；图标彻底不见了就自动关闭，不会留下空白窗口。

## 4. 菜单栏图标语义

图标只报异常，一切正常时不带徽章：

| 图标状态 | 含义 |
| --- | --- |
| 正常设备图标 | 设备就绪，权限齐全 |
| 橙点 | 缺「输入监控」或「辅助使用」权限，手势/灯效不可用 |
| 红点 | 电量低（设备自报低电量，或 < 20% 且未充电） |
| 绿点 | 正在充电（充满后消失） |
| 淡化虚线 | 设备不在，或已关机（USB 还在但不应答） |

同一时刻只显示一个，优先级：设备不在 > 缺权限 > 低电 > 充电 > 正常。

## 5. 权限

| 权限 | 用途 | 授权位置 |
| --- | --- | --- |
| 输入监控 | 通过 HID 读取旋钮/按键事件 | 系统设置 → 隐私与安全性 → 输入监控 |
| 辅助使用 | 把配置的按键动作发给前台 App | 系统设置 → 隐私与安全性 → 辅助使用 |

- 缺权限时面板顶部出现横幅，两个按钮直达对应设置页，并尽量触发系统原生弹窗。
- 每次打开面板都会重新检测，授权后重新点开即可。
- **输入监控**有时要重启 App 才生效——退出 DialPilot 再打开。
- 授权反复失效，先检查是不是用了 ad-hoc 签名（见 §1）。

### 第三种「用不了」：Ulanzi Studio 在运行

和缺权限同级：Studio 独占设备时 DialPilot 完全无法接管，面板会显示「未连接」+ 橙色横幅。点横幅里的**「退出 Ulanzi Studio」**（优雅退出，4 秒不退强制），Studio 退出后 DialPilot **自动接回，无需重启**。就算你手动退出 Studio 或它自己崩了，也一样自动接回（最迟 30 秒，打开面板立即）。开机后最常见就是这个——把 Studio 从登录项移除即根治。

## 6. 配置与自动备份

配置文件：`~/Library/Application Support/DialPilot/config.json`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `activeProfile` | `"a"` | 单组产品，恒为 a；旧配置的 b 会在启动时迁回 a |
| `offlineProfile` | `"a"` / 缺省 | 已完成设备六格备份的标记；缺省=还没写过，App 会自动补写 |
| `profileA` | 对象 | 按键映射，键为控制名，值为动作 |
| `needsHardwareSync` | bool | 内部标记：是否需要完整六格写回；**不要手改** |
| `lightMode` | `"allOn"` / `"off"` / `"smart"` | 灯效模式，默认 smart |

控制名：`knobPress`（单按）、`knobDoublePress`（双按）、`knobLeft` / `knobRight`（左右旋）、`topButton` / `middleButton` / `bottomButton`。

动作两种形态：

- 预设字符串：`"selectAll"`、`"returnKey"`、`"volumeUp"` 等（全集见 UI 下拉）。
- 组合键对象：`{"type":"shortcut","shortcut":{…}}`——建议用 UI 录制器生成（最多 4 键，区分左右修饰键）。

注意：`fnDoubleTap`、`voiceInput` 是 App-only 动作，写离线六格时对应格为空（固件存不了）。旧版的 `switchProfile` 动作已移除，旧配置里绑了它的格子解码为「不做事」。

**设备备份全自动**：改任何绑定，App 防抖 1.5 秒后把六格写回设备；设备不在就等它出现再补写。没有手动写入按钮。

## 7. Agent 灯效接入

### 状态语义

| 状态 | 灯效 | 含义 |
| --- | --- | --- |
| idle / sleeping | 全灭 | 空闲 |
| thinking | 旋钮慢闪 1.2s | 思考中 |
| working | 旋钮常亮 | 干活中 |
| attention | 中键亮 10s 自动灭 | 回合完成 |
| notification | 中+下快闪 0.6s | **需要你审批**（最高优先） |
| error | 全灯闪 3 次→恢复前态 | 出错 |
| sweeping | 三灯流水 0.5s | 压缩上下文 |

语音键灯不参与状态显示（固件按键反馈，按下松开闪一下属正常）。面板里的「灯效图解」有全屏图文说明：←/→ 或横向滑动翻页，点击任意处或 Esc 关闭。

### 安装 / 卸载

**面板方式**：灯效卡 →「接入 Agent…」→ 选 Agent → 接入 / 卸载。

- 安装前检测软件是否存在；未装会提示先装，**绝不写配置**。
- 安装 = 备份原配置（`.bak-dialpilot-<时间戳>`）→ 只新增带 `dialpilot` 标记的条目 → 读回校验。
- 卸载 = 只删标记条目，你自己的 hooks 原样保留。

**CLI 方式**：

```sh
CTL="/Applications/DialPilot.app/Contents/MacOS/dialpilotctl"
"$CTL" detect                          # 各 Agent 安装/接入状态
"$CTL" install-hooks --agent qoder     # claude-code|qwen-code|qoder|codebuddy|codex|dsh
"$CTL" uninstall-hooks --agent qoder
"$CTL" led --state working             # 手动设状态（测试）
"$CTL" led --restore                   # 恢复出厂灯效基线
"$CTL" status                          # 当前渲染状态 + 活跃会话
```

- `codebuddy` 写 `~/.workbuddy/settings.json`（WorkBuddy 真实路径）。
- `codex` 额外在 `config.toml` 开 `[features] hooks=true`，**需在 Codex 内 `/hooks` 批准**后才生效。
- `dsh` 写 `~/.dsh/profiles/web/cordis.patch.yml` 标记块，重启生效。
- hook 恒输出 `{}` 并退出 0，永不阻塞 Agent。

### 千问办公（企业旗舰版）

个人版没有 hooks 能力。企业版：面板点接入 → 本机监听启动（`127.0.0.1:27950`，仅回环）→ 复制 7 事件配置 → 企业管理后台逐条粘贴 → 跑任务看灯。卸载 = 停监听 + 后台清空规则。监听默认不启动，App 退出自动停。

### 多会话仲裁（不是 bug）

多个会话同时跑时，灯只显示最高优先级：需审批 > 出错 > 压缩 > 思考 > 干活 > 完成 > 空闲。120 秒无事件的会话自动剔除。面板会说明当前亮灯的是哪个 Agent/会话；`dialpilotctl status` 打印完整明细（`*` 标记亮灯者）。

纯净测试灯效时先卸载 hooks，否则真实会话的事件会一直压住手动状态。

## 8. 使用统计

- 计数对象：真正执行的控制事件（旋钮格、单/双按、按键点按、长按开始）。
- 存储：`~/Library/Application Support/DialPilot/usage.json`，保留 90 天日明细，累计值永久保留。
- 隐私：不联网、不含任何设备/用户标识，只有控制名与日期。
- 悬停柱状图任意一列：显示完整日期 · 当天次数 · 当天最常用控制。

删掉 `usage.json` 即可清零；损坏或缺失时按空统计启动，不会影响 App。

## 9. 验收脚本

```sh
./scripts/acceptance.sh offline   # 离线：全部自动断言（mock 设备，不碰硬件）
./scripts/acceptance.sh live      # 真机：自动断言 + 逐状态保持 + 人工项暂停
```

live 模式的人工项可输入 `s` 跳过，绝不自动通过。

## 10. 排障

| 现象 | 原因与处理 |
| --- | --- |
| `dialpilotctl` 报「DialPilot 未运行」 | App 没启动或 socket 未就绪；启动 App 等 3 秒重试 |
| **设备插着却显示未连接** | 最常见原因：Ulanzi Studio 在后台运行（尤其开机自启）。打开面板会看到橙色横幅，点「退出 Ulanzi Studio」即可，DialPilot 自动接回。根治：把 Studio 从登录项移除（系统设置 → 通用 → 登录项） |
| Studio 退出后没有自动接回 | 1.1.3 及以前的 bug（依赖的系统通知可能丢失）；1.1.4 起改为观察式检测，最迟 30 秒内自动接回，打开面板立即接回 |
| 灯完全不动 | ① Ulanzi Studio 在跑（点横幅按钮退出即自动恢复）② 设备休眠（按任意键唤醒，10s 内重放）③ 连续写失败 3 次挂起（同②自愈） |
| 设备关了，面板却曾显示已连接/旧电量 | 旧版本问题；现版本以电源查询往返判活，连续 2 次无应答即显示「未响应」并清空电量 |
| 关机后菜单栏图标变虚线 | 预期行为：USB 还在但固件不应答，按「设备不在」处理 |
| 面板出现在奇怪的位置 / 一大片空白 | 旧版本 `NSPopover` 的定位问题；现版本自持窗口，只按内容高度开窗。若仍出现请附 debug.log |
| 用 Bartender / Ice 后点图标没反应 | 图标被移入隐藏区时，面板以鼠标位置为锚点；先让图标可见再点，或把 DialPilot 加入该工具的常驻区 |
| 手动设的状态被「抢走」 | 真实 hooks 仲裁压制（见 §7），非 bug；纯净测试先卸 hooks |
| 灯亮约 10 秒自己灭 | attention 状态的预期行为（完成铃） |
| 语音键灯自己闪 | 固件按键反馈，正常，主机不可控 |
| 授权反复失效 | 用了 ad-hoc 签名；每次重编/升级都换身份（见 §1）。开关关掉再打开即可 |
| **开关是开的，权限却拿不到** | TCC 的条目按 bundle ID 显示、按**签名要求**判定。App 被替换过（升级、删除重装、换签名）就会出现「亮着但不生效」。把开关**关掉再打开**，然后重启 App |
| 升级到新版后手势/灯效全失效 | 预期行为，分发版 ad-hoc 签名的 cdhash 每版都变（见 §1「替换升级」） |
| hooks 装了没反应 | codex 需 `/hooks` 批准；dsh 需重启；其余需新会话 |
| 设备按键失灵 | App 意外退出后固件超时回原生；重启 App 即恢复在线模式 |

日志：`~/Library/Application Support/DialPilot/debug.log`。

### 开关是开的，为什么还是没权限

TCC 里一条授权 = 客户端（bundle ID）+ **签名要求（csreq）**。系统设置只按前者列条目，所以换了签名的 App 在列表里照样出现、开关照样是蓝的；真正放行时比对的是后者。ad-hoc 签名的要求就是 `cdhash H"…"`——精确到构建哈希——所以「App 被换过」和「权限失效」是同一件事的两面。

想自己确认，在**有「完全磁盘访问权限」的终端**里跑：

```sh
# 1) macOS 记的那条要求（csreq 列是 hex）
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "select service, auth_value, hex(csreq) from access
     where client = 'dev.lichengwu.dialpilot';"

# 2) 把 hex 还原成可读的要求，例如把 66610a0c… 换进下面这行
printf '%s' '66610a0c…' | xxd -r -p > /tmp/tcc-req.bin && csreq -r /tmp/tcc-req.bin -t

# 3) 当前装着的那份 App 自己声明的要求
codesign -d -r- /Applications/DialPilot.app
```

2 和 3 的 `cdhash` 不一致 = 陈旧条目。把开关关掉再打开，第 1 步那条记录的 csreq 会重写成当前 App 的，权限立即恢复。

## 11. 红线（任何操作都适用）

- 不碰固件升级 / 配对 / 重置；设备写入只限 0x0B 灯控组与已验证的六格写入。
- 测试收尾恢复基线：`dialpilotctl led --restore`。
- Studio 与 DialPilot 不同时运行。
