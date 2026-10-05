import AppKit
import Combine
import GenericID
import LyricsXFoundation
import MusicPlayer
import OpenCC
import SwiftCF
import CoreGraphicsExt

class KaraokeLyricsWindowController: NSWindowController {
    private static let windowFrame = NSWindow.FrameAutosaveName("KaraokeWindow")

    private var lyricsView = KaraokeLyricsView(frame: .zero)
    private var hasDisplayedLyrics = false

    private var cancelBag = Set<AnyCancellable>()

    init() {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isOpaque = false
        window.level = .floating
        // Treat the desktop lyric window as a transient utility in Mission Control.
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.setFrameUsingName(KaraokeLyricsWindowController.windowFrame, force: true)
        super.init(window: window)

        window.contentView = lyricsView
        lyricsView.preferredSizeDidChange = { [weak self] in
            self?.updateWindowFrame(animate: false)
        }

        addObserver()

        updateWindowFrame(animate: false)

        displayLyrics("LyricsX")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.displayLyrics("")
            AppController.shared.$currentLyrics
                .signal()
                .receive(on: DispatchQueue.lyricsDisplay)
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
            AppController.shared.$currentLineIndex
                .signal()
                .receive(on: DispatchQueue.lyricsDisplay)
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
            selectedPlayer.playbackStateWillChange
                .signal()
                .receive(on: DispatchQueue.lyricsDisplay)
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
            defaults.publisher(for: [.preferBilingualLyrics, .desktopLyricsOneLineMode])
                .prepend()
                .invoke(KaraokeLyricsWindowController.handleLyricsDisplay, weaklyOn: self)
                .store(in: &self.cancelBag)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addObserver() {
        lyricsView.bind(\.textColor, withDefaultName: .desktopLyricsColor)
        lyricsView.bind(\.progressColor, withDefaultName: .desktopLyricsProgressColor)
        lyricsView.bind(\.shadowColor, withDefaultName: .desktopLyricsShadowColor)
        lyricsView.bind(\.backgroundColor, withDefaultName: .desktopLyricsBackgroundColor)
        lyricsView.bind(\.isVertical, withDefaultName: .desktopLyricsVerticalMode, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawFurigana, withDefaultName: .desktopLyricsEnableFurigana, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawRomajin, withDefaultName: .desktopLyricsEnableRomajin, options: [.nullPlaceholder: false])

        observeDefaults(key: .desktopLyricsEnabled, options: [.new]) { [unowned self] _, _ in
            self.updateWindowVisibility()
            self.handleLyricsDisplay()
        }

        observeDefaults(key: .disableLyricsWhenSreenShot, options: [.new, .initial]) { [unowned self] _, change in
            self.window?.sharingType = change.newValue ? .none : .readOnly
        }
        observeDefaults(keys: [
            .hideLyricsWhenMousePassingBy,
            .desktopLyricsDraggable,
        ], options: [.initial]) {
            self.lyricsView.shouldHideWithMouse = defaults[.hideLyricsWhenMousePassingBy] && !defaults[.desktopLyricsDraggable]
        }
        observeDefaults(keys: [
            .desktopLyricsFontName,
            .desktopLyricsFontSize,
            .desktopLyricsFontNameFallback,
        ], options: [.initial]) { [unowned self] in
            self.lyricsView.font = defaults.desktopLyricsFont
        }

        observeNotification(name: NSApplication.didChangeScreenParametersNotification, queue: .main) { [unowned self] _ in
            self.updateWindowFrame(animate: true)
        }
        observeNotification(center: workspaceNC, name: NSWorkspace.activeSpaceDidChangeNotification, queue: .main) { [unowned self] _ in
            self.updateWindowFrame(animate: true)
        }
    }

    override func showWindow(_ sender: Any?) {
        updateWindowVisibility()
    }

    private func displayLyrics(_ firstLine: String, secondLine: String = "") {
        lyricsView.displayLrc(firstLine, secondLine: secondLine)
        hasDisplayedLyrics = !firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !secondLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        updateWindowFrame(animate: false)
        updateWindowVisibility()
    }

    private func updateWindowVisibility() {
        guard let window = window else { return }
        // Hiding only the content leaves a screen-sized, capture-excluded
        // window in the compositor and in other Spaces' preview composition.
        guard defaults[.desktopLyricsEnabled], hasDisplayedLyrics else {
            window.orderOut(nil)
            return
        }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func updateWindowFrame(toScreen: NSScreen? = nil, animate: Bool) {
        guard let screen = toScreen ?? window?.screen ?? NSScreen.screens.first else { return }
        let frame = Self.lyricWindowFrame(contentSize: lyricsView.preferredWindowSize,
                                         in: placementBounds(on: screen),
                                         xFactor: defaults[.desktopLyricsXPositionFactor],
                                         yFactor: defaults[.desktopLyricsYPositionFactor])
        guard window?.frame != frame else { return }
        window?.setFrame(frame, display: false, animate: animate)
        window?.saveFrame(usingName: KaraokeLyricsWindowController.windowFrame)
    }

    private func placementBounds(on screen: NSScreen) -> NSRect {
        let fullScreen = screen.isFullScreen || defaults.bool(forKey: "DesktopLyricsIgnoreSafeArea")
        return fullScreen ? screen.frame : screen.visibleFrame
    }

    // These coordinates position the existing desktop window only. Menu-bar
    // lyrics remain entirely inside the system-positioned NSStatusItem.
    static func lyricWindowFrame(contentSize: NSSize, in bounds: NSRect,
                                 xFactor: CGFloat, yFactor: CGFloat) -> NSRect {
        let width = min(bounds.width, max(1, contentSize.width.isFinite ? ceil(contentSize.width) : 1))
        let height = min(bounds.height, max(1, contentSize.height.isFinite ? ceil(contentSize.height) : 1))
        let x = (xFactor.isFinite ? xFactor : 0.5).clamped(to: 0 ... 1)
        let y = (yFactor.isFinite ? yFactor : 0.9).clamped(to: 0 ... 1)
        let originX = (bounds.minX + bounds.width * x - width / 2).clamped(to: bounds.minX ... bounds.maxX - width)
        let originY = (bounds.maxY - bounds.height * y - height / 2).clamped(to: bounds.minY ... bounds.maxY - height)
        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    @objc private func handleLyricsDisplay() {
        guard defaults[.desktopLyricsEnabled],
              !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying,
              let lyrics = AppController.shared.currentLyrics,
              let index = AppController.shared.currentLineIndex else {
            DispatchQueue.main.async {
                self.displayLyrics("", secondLine: "")
            }
            return
        }

        let lrc = lyrics.lines[index]
        let next = lyrics.lines[(index + 1)...].first { $0.enabled }

        let languageCode = lyrics.metadata.translationLanguages.first

        var firstLine = lrc.content
        var secondLine: String
        var secondLineIsTranslation = false
        if defaults[.desktopLyricsOneLineMode] {
            secondLine = ""
        } else if defaults[.preferBilingualLyrics],
                  let translation = lrc.attachments[.translation(languageCode: languageCode)] {
            secondLine = translation
            secondLineIsTranslation = true
        } else {
            secondLine = next?.content ?? ""
        }

        if let converter = ChineseConverter.shared {
            if lyrics.metadata.language?.hasPrefix("zh") == true {
                firstLine = converter.convert(firstLine)
                if !secondLineIsTranslation {
                    secondLine = converter.convert(secondLine)
                }
            }
            if languageCode?.hasPrefix("zh") == true {
                secondLine = converter.convert(secondLine)
            }
        }

        DispatchQueue.main.async {
            self.displayLyrics(firstLine, secondLine: secondLine)
            if let upperTextField = self.lyricsView.displayLine1,
               let timetag = lrc.attachments.timetag {
                let position = selectedPlayer.playbackTime
                let timeDelay = AppController.shared.currentLyrics?.adjustedTimeDelay ?? 0
                let progress = timetag.tags.map { ($0.time + lrc.position - timeDelay - position, $0.index) }
                upperTextField.setProgressAnimation(color: self.lyricsView.progressColor, progress: progress)
                if !selectedPlayer.playbackState.isPlaying {
                    upperTextField.pauseProgressAnimation()
                }
            }
        }
    }

    // MARK: Dragging

    private var vecToCenter: CGVector?

    override func mouseDown(with event: NSEvent) {
        let location = lyricsView.convert(event.locationInWindow, from: nil)
        vecToCenter = CGVector(from: location, to: lyricsView.bounds.center)
    }

    override func mouseDragged(with event: NSEvent) {
        guard defaults[.desktopLyricsDraggable],
              let vecToCenter = vecToCenter,
              let window = window else {
            return
        }
        var center = event.locationInWindow + vecToCenter
        let centerInScreen = window.convertToScreen(CGRect(origin: center, size: .zero)).origin
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(centerInScreen) }) ?? window.screen else { return }
        let bounds = placementBounds(on: screen)
        guard bounds.width > 0, bounds.height > 0 else { return }
        center = CGPoint(x: centerInScreen.x - bounds.minX, y: centerInScreen.y - bounds.minY)

        var xFactor = (center.x / bounds.width).clamped(to: 0 ... 1)
        var yFactor = (1 - center.y / bounds.height).clamped(to: 0 ... 1)
        if abs(center.x - bounds.width / 2) < 8 {
            xFactor = 0.5
        }
        if abs(center.y - bounds.height / 2) < 8 {
            yFactor = 0.5
        }
        defaults[.desktopLyricsXPositionFactor] = xFactor
        defaults[.desktopLyricsYPositionFactor] = yFactor
        updateWindowFrame(toScreen: screen, animate: false)
    }
}

extension NSScreen {
    fileprivate var isFullScreen: Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return !windowInfoList.contains { info in
            guard info[kCGWindowOwnerName as String] as? String == "Window Server",
                  info[kCGWindowName as String] as? String == "Menubar",
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary as CFDictionary?,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                return false
            }
            return frame.contains(bounds)
        }
    }
}
