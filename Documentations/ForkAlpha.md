# Fork alpha

Experimental builds from `SmallSquare/LyricsX`, on
`codex/develop-avrcp-controls`. Upstream remains
[MxIris-LyricsX-Project/LyricsX](https://github.com/MxIris-LyricsX-Project/LyricsX).

## Current integration branch

Based on upstream `develop` at `f0175be`. Menu-bar rendering uses upstream's
`NSControl` / `NSTextFieldCell` implementation unchanged, with its default
60 fps cap and no static-paging or visible frame-rate setting. The previous
`MenuBarLyricsFrameRate` preference is not read by this branch.

The fork retains the content-sized desktop lyrics window / Mission Control
workaround, compact dropdown playback controls, and AVRCP phone source with
automatic selection. It also includes the verified phone transition and artwork
fallback improvements made after alpha.1. The published alpha.1 download does
not contain this integration.

本分支基于上游 `develop` 的 `f0175be`，采用上游菜单栏渲染及默认 60 fps 上限，
不含原静态分页和可见帧率选项，原帧率偏好不再读取。保留桌面歌词黑屏修复、
下拉播放控制、AVRCP 手机来源及自动选择，以及后续切歌和联网补封面改进。
已发布的 alpha.1 不含本次整合。

## Download and use

Download the arm64 ZIP from [fork releases](https://github.com/SmallSquare/LyricsX/releases),
extract it, quit any running LyricsX, and move `LyricsX(alpha).app` into Applications.
Keep a copy of your previous app so you can return to it. This build uses the same
bundle identifier, preferences and lyric library as upstream; run only one copy.
The Homebrew package linked by upstream does not install this fork.

- Apple Silicon, macOS 12 or later. The new menu-bar renderer requires macOS 26;
  earlier systems keep the original renderer. Real-device testing has been on macOS 27.
- Ad-hoc signed, not Apple-notarized. macOS may block the first launch. This package
  does not provide the provisioning needed for iCloud or App Group-dependent features.
- Automatic updates are disabled in alpha packages. Install later alphas manually.
- Pair the phone in macOS Bluetooth settings first, then select it under Preferences →
  AVRCP. Select Automatic or AVRCP in General. Compatibility varies by phone and OS.
- Enable or disable the compact playback card in Preferences → Lab. The upstream
  menu-bar playback buttons have their own separate setting.

In `v1.9.0-alpha.1`, Bluetooth song metadata, playback position and lyric changes were exercised with an
iPhone. Universal phone support has not been established. Bluetooth cover art remains
unavailable in the tested setup; no web artwork fallback is used for phones. Absolute
seek is disabled for AVRCP. Notification subscriptions are used when supported, with
bounded fallback queries. Reconnection can still require opening Bluetooth settings
on the phone. No phone companion app is required.

## Development changes after alpha.1

The development branch can use upstream online artwork lookup when the selected
AVRCP phone cannot supply a Bluetooth cover. The Lab high-resolution artwork
option controls this fallback as well as the lyrics panel. It uses iTunes and
artwork URLs supplied by matched lyrics, validates track metadata and caches
successful results. Bluetooth images take priority; switching tracks clears the
previous cover before the next one loads. This does not add Bluetooth cover
support, and the published alpha.1 package does not include this change.

## Build and package

Use Xcode with the Metal toolchain installed and the repository's locked Swift packages.
From a clean checkout of the release tag:

```sh
LYRICSX_SKIP_BUILD_BUMP=1 xcodebuild \
  -project LyricsX.xcodeproj -scheme LyricsX -configuration Release \
  -derivedDataPath .build/AlphaDerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

python3 Scripts/release/package-alpha.py \
  --version 1.9.0-alpha.1 \
  --source-app .build/AlphaDerivedData/Build/Products/Release/LyricsX.app \
  --output outputs/alpha/1.9.0-alpha.1
```

The packaging script changes only the copied app's metadata, isolates its update feed,
removes upstream provisioning profiles, applies an ad-hoc signature, verifies both the
app and extracted ZIP, and writes `SHA256SUMS` plus a manifest containing the source
commit. It never installs the app or publishes a release. The inherited official
release workflow runs only in the upstream repository.

---

此 alpha 来自 `SmallSquare/LyricsX` 的功能开发分支。下载 ZIP 后，退出正在运行的
LyricsX，将 `LyricsX(alpha).app` 移入“应用程序”。建议保留原版本；两者共享设置和歌词库，
不要同时运行。上游 Homebrew 包不包含这些实验功能。

支持 Apple Silicon、macOS 12 及以上；新的菜单栏渲染器用于 macOS 26 及以上，实机测试环境为
macOS 27。采用临时签名，未经 Apple 公证，首次启动可能被系统拦截；此包不提供 iCloud、
App Group 相关功能所需的授权配置。自动更新已关闭，后续版本需手动安装。

手机先在系统蓝牙设置中配对，再到“偏好设置 → AVRCP”选择设备；通用页可以选“自动选择”
或“AVRCP”。菜单下拉音乐控制器的开关在实验室；上游菜单栏播放按钮有单独开关。

已在 iPhone 上验证歌曲信息、播放进度和切歌歌词同步，不代表所有手机均已兼容。
已发布的 alpha.1 中，蓝牙封面在已测试环境仍不可用，也不通过网络补查；
本开发分支可在蓝牙无法提供封面时，按实验室高清封面开关联网补查。蓝牙进度条不支持拖动。
优先使用通知，缺少通知时有有限补查；重连有时仍需打开手机蓝牙设置。无需手机配套 App。

上面的命令可构建和打包。脚本只操作构建副本，校验签名和解压结果，生成校验和及源码提交记录；
不会安装应用或自动发布。
