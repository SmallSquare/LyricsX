# LyricsX 原生菜单栏自绘实验

菜单栏歌词六档设置的 UI 与重启持久化验收已完成，详见 [settings-ui-acceptance.md](settings-ui-acceptance.md)。本次交付为 `outputs/LyricsX-Settings.zip`；旧 Native 包不包含设置页。

基于 LyricsX v1.8.9（`0e077101a176ab9efc6b506074a52d5ab0217e75`），分支 `codex/native-drawn-marquee`。

参考 ClashX.Meta issue 166 中 `forget-pro/ClashX.Meta` 的提交 `bb4ef4e7ca990dd26effff7c278499fed0bd1682`：避开菜单栏内的 `NSTextField`，使用自绘 `NSView`。

## 实现

- macOS 26 及以上采用 `NativeMarqueeView`，旧系统沿用 MarqueeLabel。
- 仍由 `NSStatusItem.button` 承载歌词；不创建浮动面板或自行计算屏幕位置。
- 每句歌词只栅格化一次，绘制缓存文字的透明度遮罩；长句按原控件的时间比例停留、滚动、停留。默认滚动刷新上限 30 fps。
- 相同歌词和时长不重新生成图像或重启动画。
- 暂停时冻结滚动进度；短文字、滚动结束、控件隐藏或离开窗口时不运行滚动计时器。
- 系统颜色在绘制时解析，保留深浅外观适配。

## 控件对照测量

环境：macOS 27.0（26A428），Apple Silicon，一块 1800 × 1169 点、2 倍缩放屏幕。每次仅运行一个独立菜单栏进程，文字宽度 183 点，字号 14；长句每 10 秒交替。CPU 为该进程 `getrusage` 用户态与内核态时间之和 / 墙钟时间，100% 代表一个 CPU 核心。

| 场景 | 原 MarqueeLabel | 新自绘控件 |
| --- | ---: | ---: |
| 静态短文字，20 秒 | 35.86% | 0.15% |
| 长句滚动，40 秒 | 38.27% | 13.01%（30 fps） |
| 长句滚动，40 秒 | — | 9.92%（24 fps 额外实验） |

这是各一次短期控件实验，不能当作完整 LyricsX、WindowServer、MenuBarAgent 的整体降耗或耗电数据。生产代码保留 30 fps。图层缓存与原生按钮图像实验没有充分优势，未纳入最终实现。

生命周期测试 `LifecycleProbe.swift` 的 24 项检查通过：原有短句、滚动、重复更新、暂停恢复、脱离/重新挂回、隐藏/重新显示、结束、调整宽度及无效输入检查，以及静态换句、静态转滚动、五个滚动档位切换、立即切回静态和暂停期间切档检查。

`outputs/` 中的构建包、截图和原始采样保留在本地，不随源码提交。`history/` 中的对话、迁移清单和交接索引也仅保留在本地。面向上游审查的范围与复现入口见 [upstream-pr-notes.md](upstream-pr-notes.md)。

## 复现控件测试

在项目根目录执行（需要 macOS AppKit 与 Xcode）：

```sh
xcrun clang -O2 -fobjc-arc -mmacosx-version-min=11.0 -c validation/OriginalMarqueeLabel.m -o validation/OriginalMarqueeLabel.o
xcrun swiftc -O -target arm64-apple-macosx11.0 -import-objc-header validation/MLMarqueeLabel.h LyricsX/Controller/NativeMarqueeView.swift validation/MarqueeProbe.swift validation/OriginalMarqueeLabel.o -o validation/MarqueeProbe
validation/MarqueeProbe --renderer original --scenario scroll --duration 40
validation/MarqueeProbe --renderer native --scenario scroll --duration 40
xcrun swiftc -O -target arm64-apple-macosx11.0 LyricsX/Controller/NativeMarqueeView.swift validation/LifecycleProbe.swift -o validation/LifecycleProbe
validation/LifecycleProbe
```

性能测试期间应停止编译，且不要同时运行其他歌词测试程序。`OriginalMarqueeLabel.m` 与 `MLMarqueeLabel.h` 来自项目锁定的 MarqueeLabel 0.1.0，用于相同环境对照。

## 尚需现场验证

完整 Release App 编译成功，并通过 `codesign --verify --deep --strict`；启动正常，实际歌曲歌词能够显示。

追加真实英文歌测试：播放资料库中的 Taylor Swift《Lover》，通过音乐 App 的歌词定位到第二段主歌约 1:32 的长句。连续菜单栏截图观察到同一句文字由开头向左滚动到末尾，始终裁剪在原生菜单项范围内。菜单栏展开和重新折叠后未见覆盖邻近图标。此检查验证了可见的滚动与基本折叠行为；截图采样不能量化每帧流畅度。

完整 App 测量（累计 CPU 时间差，原始 JSON 在 `outputs`）：

| 场景 | LyricsX 平均 CPU | 最高约 1 秒区间 |
| --- | ---: | ---: |
| Lover 长短句交替，45.65 秒 | 5.17% | 30.50% |
| Lover 第二段主歌长句测试，35.41 秒 | 5.53% | 27.82% |

上述真实 App 测试期间进行了菜单栏截图和歌词定位，包含换句与停留阶段，不能把平均值当作持续滚动的瞬时 CPU，也没有同段歌曲原版 A/B。后一次测量的 MenuBarAgent 平均约 0.73%、WindowServer 约 63.42%；桌面上其他 App 也在运行，没有做系统负载归因或耗电验收。

全屏和多屏切换仍须验证。当前只有一块屏幕；原生结构减少了此前浮动面板的位置管理问题，但不能据此声称多屏已通过。

此试用构建使用本地 ad-hoc 签名，未公证。iCloud 等需要开发者配置的能力不属于本次试用验证。不要用试用包覆盖现有 `/Applications/LyricsX.app`；从 `outputs` 独立运行即可，退出后可重新打开原版。

完整构建使用 Xcode 的 Release 配置、arm64 架构和本地缓存依赖；禁用开发者签名构建后，单独用仅含 Apple Events 能力的本地 entitlements 签名。开发者 entitlement 源文件保持不变。现有 LyricsX 安装未被覆盖；测试版与原版使用同一 Bundle ID，读取现有偏好和歌词库。

## 2026-10-03 完整 App 帧率短测

按用户要求停止需要静置前台的长时间整机功耗测试，已关闭测试窗口并恢复普通 30 fps 试用构建。以下只使用已经完成的短测；未完成、前台状态未确认的整机遥测不用于结论。macOS 26 之前的开销保留未知。

环境为 M4 MacBook Pro、macOS 27.0（26A428）、最高 120 Hz 的内建屏幕。Release App 的 `LYRICSX_BENCHMARK` 编译条件提供受控输入：原生 `NSStatusItem.button`，183 点宽，14 点字号，固定英文长句每 8 秒更换末尾的数字。原版指锁定的 MarqueeLabel 0.1.0 / NSTextField 动画路径；静态指新的自绘方案暂停滚动但仍每 8 秒换句。完整 App 的普通后台组件保留，菜单栏歌词的实际歌曲订阅由固定输入替代。CPU 并非独立控件测量。

各档两轮，每轮 32 秒；计量前预热 8 秒，前后穿插关闭菜单栏歌词的基线。CPU 使用进程累计 CPU 时间差，100% 表示一个核心；包含换句、停留和滚动。滚动更新频率在另一次独立运行中只记录位置改变时间，排除停留及回到开头的阶段，避免高频轮询影响 CPU 对照。

| 方案 / 目标 fps | 滚动位置更新 / 秒 | LyricsX 平均 CPU | 两轮 CPU 范围 |
| --- | ---: | ---: | ---: |
| 自绘静态 | 0 | 0.30% | 0.16–0.44% |
| 自绘 24 | 23.95 | 13.12% | 12.79–13.45% |
| 自绘 30（当前默认） | 29.95 | 13.85% | 11.76–15.94% |
| 自绘 60 | 60.01 | 22.00% | 20.62–23.37% |
| 自绘 90 | 88.46 | 23.80% | 23.27–24.33% |
| 自绘 120 | 115.46 | 26.55% | 24.27–28.83% |
| 原版默认动画 | 104.67 | 36.49% | 35.71–37.27% |

原版代码没有指定 fps，采用 NSAnimationContext / NSView animator 更新 frame。在这台机器上，位置更新间隔中位数 8.3406 ms，约为 120 Hz 的节奏；4 次滚动周期有效更新率为 101.78–107.50 次/秒，合计 104.67 次/秒。因此不能将“未指定 fps”解释为固定 60 fps。这里只测到了位置更新，未测面板实际呈现 FPS，也不能推断所有 Mac 或旧 macOS 使用同一节奏。

本次受控长句测试中，30 档 LyricsX 平均 CPU 比原版低约 62%；即使提高到 120 档，自绘仍低约 27%。这些是当前样本的描述性对照，不是所有歌曲的 CPU 或节电保证。

系统组件的 CPU 为相对前后关闭基线线性插值得到的差值（百分点）；芯片功率由 `powermetrics` 的 CPU + GPU + ANE 相加，单位 W。下表是短测均值，不代表已隔离的因果增量。

| 方案 | MenuBarAgent CPU 差值 | WindowServer CPU 差值 | ControlCenter CPU 差值 | 芯片功率差值及两轮范围 |
| --- | ---: | ---: | ---: | ---: |
| 自绘静态 | +0.06 | −1.71 | +0.11 | +0.11 W（仅一轮） |
| 自绘 24 | +0.94 | −0.02 | −0.23 | −0.48 W（−1.62 至 +0.65） |
| 自绘 30 | +6.88 | +11.90 | +0.18 | +0.98 W（−0.22 至 +2.17） |
| 自绘 60 | +2.53 | −1.17 | −0.06 | −0.29 W（−0.86 至 +0.29） |
| 自绘 90 | +3.04 | +0.13 | +0.85 | −0.20 W（−1.46 至 +1.06） |
| 自绘 120 | +4.52 | +8.00 | −0.20 | +0.58 W（+0.58 至 +0.59） |
| 原版默认 | +6.96 | +7.69 | +0.04 | +0.83 W（+0.33 至 +1.34） |

后台活动未受控，30 档第二轮的 WindowServer / GPU 明显升高，系统组件和芯片功率不呈稳定的单调趋势；负值反映基线及后台波动，不能解释为开启歌词省电。两轮范围不是置信区间。重启测试 App 会触发原生菜单栏折叠，本批包含折叠状态，无法代表始终展开时的合成成本。应用侧 CPU 和位置更新已记录，但可见呈现效果及系统合成负载仍有这些限制。

`powermetrics` 共取得 900 个约 2 秒样本，按阶段时间保留完整采样区间并扣除前后基线。静态第二轮功率覆盖不足，已排除其功率差值。芯片功率不包含显示屏等其他部件，不能用它代替整机功耗增量。电池/固件整机遥测未经校准且对照未完成，因此整机增量 W、节电比例和续航变化均未可靠确定。

曲线为 `outputs/fps-study/fps-cpu-power.png`，另有 SVG 和 PDF。原始阶段、位置时间戳、连续功率日志、汇总及质量说明保存在同目录。`cpu-soc-results.csv` 和 `results.json` 保存逐轮结果；`measurement-quality.json` 记录整机测试停止及测量限制。作图脚本为 `validation/plot-fps-study.py`；它不绘制未完成的整机数据。
