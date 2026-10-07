# LyricsX

> [!IMPORTANT]
> This branch is the experimental SmallSquare fork of [MxIris-LyricsX-Project/LyricsX](https://github.com/MxIris-LyricsX-Project/LyricsX). It uses upstream develop’s menu-bar renderer and adds the Mission Control workaround, a compact playback menu, and a Bluetooth AVRCP phone source.
>
> **Fork alpha downloads:** [SmallSquare releases](https://github.com/SmallSquare/LyricsX/releases). Read the [alpha notes and build instructions](Documentations/ForkAlpha.md) for requirements and known limitations. The Homebrew instructions below install the upstream release, not this alpha.
>
> 此分支基于最新上游 develop 的菜单栏渲染，保留黑屏修复、音乐控制和蓝牙手机来源。[下载 alpha](https://github.com/SmallSquare/LyricsX/releases) 前请阅读[试用说明](Documentations/ForkAlpha.md)；下方 Homebrew 安装的是上游版本。

<img src="docs/img/icon.png" width="128px">

Ultimate lyrics app for macOS.

[LyricsX for iOS](https://github.com/ddddxxx/LyricsX-iOS) and [lyricsx-cli for Linux](https://github.com/ddddxxx/lyricsx-cli) is in early development.

## Installation

### Homebrew

```
brew tap brewforge/extras
brew install brewforge/extras/lyricsx-mxiris
```

### Manual

Download from [releases](https://github.com/MxIris-LyricsX-Project/LyricsX/releases).

To use **Musixmatch** as lyrics source, you need to follow the steps provided [here](https://gist.github.com/TrueMyst/0461aea999e347182486934fd83a4cf9) or [here](https://spicetify.app/docs/faq#sometimes-popup-lyrics-andor-lyrics-plus-seem-to-not-work) to obtain a **usertoken** and fill it in LyricsX's preferences.

### Requirements

- macOS 12+ (fork alpha binary: Apple Silicon; see the alpha notes)

## Features

- Work perfectly with your favorite music players. [List of supported players](https://github.com/ddddxxx/MusicPlayer#supported-players)
- Automatically search & download live lyrics from various lyrics sources. [List of supported sources](https://github.com/ddddxxx/LyricsKit#supported-sources)
- Display lyrics on desktop and menubar. you can customize font, color and position.
- Adjust lyrics offset on status menu.
- Navigate the song with lyrics - Double click a line to jump to specific position.
- Drag & Drop to import/export lyrics file.
- Auto launch & quit with music player.
- Automatic conversion between Traditional Chinese and Simplified Chinese.

### Lyrics Editor

LyricsX use custom lyrics file format "LRCX" which support word time tag, multi-language translation and more. Currently there's no official LRCX editor. You can use [Lrcx_Creator](https://github.com/Doublefire-Chen/Lrcx_Creator) for now (see [#544](https://github.com/ddddxxx/LyricsX/issues/544), thanks to [@Doublefire-Chen](https://github.com/Doublefire-Chen)). Or use normal LRC editor, as LRCX is compatible with LRC.

## Screenshot

<img src="docs/img/desktop_lyrics.gif" width="480px">

<img src="docs/img/preview_1.jpg" width="1280px">

<img src="docs/img/preview_2.jpg" width="1280px">

<img src="docs/img/preview_3.jpg" width="1280px">

## Credit

#### Components

- [LyricsKit](https://github.com/ddddxxx/LyricsKit)
- [MusicPlayer](https://github.com/ddddxxx/MusicPlayer)

#### Open Source Libraries

- [SwiftyOpenCC](https://github.com/ddddxxx/SwiftyOpenCC)
- [GenericID](https://github.com/ddddxxx/GenericID)
- [SwiftCF](https://github.com/ddddxxx/SwiftCF)
- [Regex](https://github.com/ddddxxx/Regex)
- [Semver](https://github.com/ddddxxx/Semver)
- [TouchBarHelper](https://github.com/ddddxxx/TouchBarHelper)
- [CombineX](https://github.com/cx-org/CombineX)
- [SnapKit](https://github.com/SnapKit/SnapKit)
- [MASShortcut](https://github.com/shpakovski/MASShortcut)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Then](https://github.com/devxoul/Then)

#### Special Thanks

- [Lyrics Project](https://github.com/MichaelRow/Lyrics)


## ⚠️ Disclaimer

All lyrics are property and copyright of their owners.
