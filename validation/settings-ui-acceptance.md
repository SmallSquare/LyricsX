# 菜单栏歌词设置验收（2026-10-03）

验收应用：`outputs/LyricsX-Settings.app`，arm64 Release，基于官方 v1.8.9 / `0e077101a176ab9efc6b506074a52d5ab0217e75`。环境为 macOS 27.0（26A428），简体中文、深色外观、内建屏幕。操作使用原生 UI；未覆盖 `/Applications/LyricsX.app`，未调整音乐播放，未重做功耗实验。

## 实际 UI 验收

- “偏好设置 → 显示”包含“逐行 / 窗口 / 菜单栏歌词”三个标签页；新页的标签、选择控件、帮助文字无截断或重叠。
- 初次进入显示 30 fps；弹出菜单恰有静态 / 24 / 30 / 60 / 90 / 120 六档。
- 逐一通过 UI 选择全部六档，选择控件立即显示对应值。
- 选择静态后，用户偏好文件的 `MenuBarLyricsFrameRate` 为 0；选择 24 fps 后为 24。读取的是实际 `~/Library/Preferences/com.JH.LyricsX.plist`，未用命令写入测试值。
- 选择 24 fps 后关闭、重开设置，仍显示 24 fps。
- 用 UI 退出应用，确认进程消失，然后从同一精确路径重启；再次进入新页仍显示 24 fps。此项验证了非默认值的重启持久化。
- 最后通过 UI 恢复 30 fps，偏好文件确认值为 30，并关闭设置窗口。设置版留在后台运行。

截图保存在 `outputs/settings-ui/`：`static.png`、`options.png`、`reopened-24.png`、`restarted-24.png`、`final-30.png`；最终可访问性树为 `final-ax.txt`。无窗口的菜单栏应用使用 Finder 精确路径的“打开”命令重开设置；首次重开会被应用既有逻辑忽略，下一次打开显示设置。

## 行为与构建证据

`outputs/settings-lifecycle.log` 已有 24 项 PASS，覆盖静态长句不滚动、静态正常换句、切回滚动、全部档位切换及暂停恢复。UI 写入链路在本次验收通过；`MenuBarLyricsController` 订阅该偏好并在主线程更新 `NativeMarqueeView.frameRate`，启动时 prepend 持久化值。静态转滚动会重置当前句计时。此处没有用真实歌曲截图重新验收每一档的运动，也没有测面板呈现 FPS。

Release 构建成功见 `outputs/settings-build.log`；本次重新执行 `codesign --verify --deep --strict` 通过，工作区和暂存区 `git diff --check` 均通过。没有为 UI 验收修改实现代码。

## 交付与范围

本次设置版为 `outputs/LyricsX-Settings.zip`；补丁为 `outputs/native-drawn-marquee-settings.patch`。校验值及打包记录见 `outputs/settings-delivery.json`。旧 `LyricsX-Native.app`、ZIP 和旧补丁保留原样，不能作为包含设置的新版本交付。

试用包为本地 ad-hoc 签名、未公证；iCloud 能力未验收。旧系统上的禁用提示仅由代码检查支持，用户已取消旧系统测试。全屏、多屏与其他语言外观未现场验收。历史芯片功率、当前有干扰的芯片短测及未知的整机功耗仍保持原有区分。
