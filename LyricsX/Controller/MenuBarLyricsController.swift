import AppKit
import Combine
import GenericID
import LyricsXFoundation
import MusicPlayer
import OpenCC
import SwiftCF
import AccessibilityExt
import MarqueeLabel

class MenuBarLyricsController {
    static let shared = MenuBarLyricsController()

    var statusBarMenu: NSMenu? {
        didSet {
            setupStatusItemMenu()
        }
    }

    private var iconStatusItem: NSStatusItem?
    private var lyricStatusItem: NSStatusItem?
    private var buttonImage = #imageLiteral(resourceName: "status_bar_icon")
    private var buttonlength: CGFloat = 30

    private var marqueeLabel: NSView = {
        let frame = NSRect(x: 0, y: 0, width: 183, height: 22)
        #if LYRICSX_BENCHMARK
        if ProcessInfo.processInfo.environment["LYRICSX_BENCH_MODE"] == "original" {
            return MarqueeLabel(frame: frame)
        }
        #endif
        if #available(macOS 26, *) {
            return NativeMarqueeView(frame: frame)
        }
        return MarqueeLabel(frame: frame)
    }()

    private var lastDisplayMode: DisplayMode?

    private enum DisplayMode {
        case separate
        case combine
    }

    private static let defaultLyric = "LyricsX"

    private var screenLyrics: (lyrics: String, duration: TimeInterval) = (MenuBarLyricsController.defaultLyric, 2) {
        didSet {
            #if LYRICSX_BENCHMARK
            if ProcessInfo.processInfo.environment["LYRICSX_BENCH_MODE"] != nil { return }
            #endif
            DispatchQueue.main.async {
                self.updateStatusItems()
            }
        }
    }

    private var cancelBag = Set<AnyCancellable>()

    #if LYRICSX_BENCHMARK
    private var benchmarkTimer: Timer?
    private var benchmarkLine = 0
    private var benchmarkBackdrop: NSWindow?
    private var benchmarkControlTimer: Timer?
    private var benchmarkCommand = ""
    private var benchmarkObserver: NSObjectProtocol?
    private var benchmarkFrames: [[String: Double]] = []
    #endif

    private init() {
        #if LYRICSX_BENCHMARK
        if let mode = ProcessInfo.processInfo.environment["LYRICSX_BENCH_MODE"] {
            setupBenchmark(mode: mode)
            return
        }
        #endif
        if !defaults[.hideMenuBarItems] {
            updateStatusItems()
        }
        AppController.shared.$currentLyrics
            .combineLatest(AppController.shared.$currentLineIndex)
            .receive(on: DispatchQueue.lyricsDisplay)
            .invoke(MenuBarLyricsController.handleLyricsDisplay, weaklyOn: self)
            .store(in: &cancelBag)
        workspaceNC
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .signal()
            .invoke(MenuBarLyricsController.updateStatusItems, weaklyOn: self)
            .store(in: &cancelBag)
        defaults.publisher(for: [.menuBarLyricsEnabled, .combinedMenubarLyrics, .hideMenuBarItems])
            .prepend()
            .invoke(MenuBarLyricsController.updateStatusItems, weaklyOn: self)
            .store(in: &cancelBag)
        defaults.publisher(for: .menuBarLyricsFrameRate)
            .prepend(defaults[.menuBarLyricsFrameRate])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                let supported = [0, 24, 30, 60, 90, 120]
                (self?.marqueeLabel as? NativeMarqueeView)?.frameRate = Double(supported.contains(rate) ? rate : 30)
            }
            .store(in: &cancelBag)
        (marqueeLabel as? NativeMarqueeView)?.setPlaybackPaused(!selectedPlayer.playbackState.isPlaying)
        selectedPlayer.playbackStateWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                (self?.marqueeLabel as? NativeMarqueeView)?.setPlaybackPaused(!state.isPlaying)
            }
            .store(in: &cancelBag)
    }

    private func handleLyricsDisplay(event: (lyrics: Lyrics?, index: Int?)) {
        guard let lyrics = event.lyrics, let index = event.index else {
            // A new song can need time to load. Never keep the previous song's line.
            if screenLyrics.lyrics != Self.defaultLyric { screenLyrics = (Self.defaultLyric, 2) }
            return
        }
        guard !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying else { return }
        let currentLine = lyrics.lines[index]
        var newScreenLyrics = currentLine.content
        if let converter = ChineseConverter.shared, lyrics.metadata.language?.hasPrefix("zh") == true {
            newScreenLyrics = converter.convert(newScreenLyrics)
        }
        if newScreenLyrics == screenLyrics.lyrics {
            return
        }
        let lineDisplayTime: TimeInterval
        if let duration = currentLine.attachments.timetag?.duration {
            lineDisplayTime = duration
        } else if let nextLine = lyrics.lines[safe: index + 1] {
            lineDisplayTime = nextLine.position - currentLine.position
        } else {
            lineDisplayTime = 2
        }
        screenLyrics = (newScreenLyrics, lineDisplayTime)
    }

    @objc private func updateStatusItems() {
        guard !defaults[.hideMenuBarItems] else {
            marqueeLabel.removeFromSuperview()
            iconStatusItem = nil
            lyricStatusItem = nil
            lastDisplayMode = nil
            return
        }

        guard defaults[.menuBarLyricsEnabled] else {
            marqueeLabel.removeFromSuperview()
            if iconStatusItem == nil {
                setupIconStatusItem()
            }
            lyricStatusItem = nil
            lastDisplayMode = nil
            return
        }

        if defaults[.combinedMenubarLyrics] {
            updateCombinedStatusLyrics()
            lastDisplayMode = .combine
        } else {
            updateSeparateStatusLyrics()
            lastDisplayMode = .separate
        }
    }

    private func updateSeparateStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .combine {
            setupIconStatusItem()
            setupLyricStatusItem()
        }

        updateMarqueeText()
    }

    private func updateCombinedStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .separate {
            iconStatusItem = nil
            setupLyricStatusItem()
        }

        updateMarqueeText()
    }

    private func updateMarqueeText() {
        if let label = marqueeLabel as? NativeMarqueeView {
            label.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
        } else if let label = marqueeLabel as? MarqueeLabel {
            label.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
        }
    }

    private func setupLyricStatusItem() {
        marqueeLabel.removeFromSuperview()
        lyricStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        lyricStatusItem?.button?.title = ""
        lyricStatusItem?.button?.image = nil
        lyricStatusItem?.length = NSStatusItem.variableLength
        lyricStatusItem?.button?.frame = marqueeLabel.bounds
        lyricStatusItem?.button?.addSubview(marqueeLabel)
        setupStatusItemMenu()
    }

    private func setupIconStatusItem() {
        iconStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        iconStatusItem?.button?.title = ""
        iconStatusItem?.button?.image = buttonImage
        iconStatusItem?.length = buttonlength
        setupStatusItemMenu()
    }


    #if LYRICSX_BENCHMARK
    private func applyBenchmarkCommand(mode: String, fps: Double) {
        benchmarkTimer?.invalidate()
        benchmarkTimer = nil
        marqueeLabel.removeFromSuperview()
        if mode == "off" { return }
        if mode == "original" && !(marqueeLabel is MarqueeLabel) {
            marqueeLabel = MarqueeLabel(frame: NSRect(x: 0, y: 0, width: 183, height: 22))
        } else if mode != "original" && !(marqueeLabel is NativeMarqueeView) {
            marqueeLabel = NativeMarqueeView(frame: NSRect(x: 0, y: 0, width: 183, height: 22))
        }
        lyricStatusItem?.button?.addSubview(marqueeLabel)
        if let native = marqueeLabel as? NativeMarqueeView {
            native.frameRate = fps
            native.setPlaybackPaused(false)
            native.setStringValue("", lineDisplayTime: 8)
        }
        let update: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.benchmarkLine += 1
            self.screenLyrics = ("When the night turns quiet I can hear every distant voice calling me back home \(self.benchmarkLine % 2)", 8)
            self.updateMarqueeText()
            if mode == "static" { (self.marqueeLabel as? NativeMarqueeView)?.setPlaybackPaused(true) }
        }
        update()
        benchmarkTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in update() }
    }

    private func setupBenchmark(mode: String) {
        setupIconStatusItem()
    if ProcessInfo.processInfo.environment["LYRICSX_BENCH_QUIET_WINDOW"] == "1", let screen = NSScreen.main {
        let window = NSWindow(contentRect: screen.visibleFrame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "LyricsX 帧率与功耗测试 — 静态画面"
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        benchmarkBackdrop = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
        if let control = ProcessInfo.processInfo.environment["LYRICSX_BENCH_CONTROL"] {
            setupLyricStatusItem()
            let tick: () -> Void = { [weak self] in
                guard let self = self, let command = try? String(contentsOfFile: control, encoding: .utf8), command != self.benchmarkCommand,
                      let data = command.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let mode = object["mode"] as? String else { return }
                self.benchmarkCommand = command
                self.applyBenchmarkCommand(mode: mode, fps: object["fps"] as? Double ?? 30)
            }
            tick()
            benchmarkControlTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
            return
        }
        guard mode != "off" else { return }
        setupLyricStatusItem()
        if let native = marqueeLabel as? NativeMarqueeView {
            native.frameRate = Double(ProcessInfo.processInfo.environment["LYRICSX_BENCH_FPS"] ?? "30") ?? 30
        }
        if let path = ProcessInfo.processInfo.environment["LYRICSX_BENCH_TRACE"] {
            let record: (CGFloat) -> Void = { [weak self] x in
                guard let self = self else { return }
                self.benchmarkFrames.append(["t": ProcessInfo.processInfo.systemUptime, "x": Double(x)])
            }
            if let field = marqueeLabel.subviews.first as? NSTextField {
                field.postsFrameChangedNotifications = true
                benchmarkObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: field, queue: nil) { _ in record(field.frame.origin.x) }
            } else if let native = marqueeLabel as? NativeMarqueeView {
                native.benchmarkOffsetObserver = record
            }
            benchmarkTimer = Timer.scheduledTimer(withTimeInterval: 32, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                var value: [String: Any] = ["frames": self.benchmarkFrames]
                if #available(macOS 12, *) { value["max_screen_fps"] = NSScreen.screens.map { $0.maximumFramesPerSecond } }
                if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: URL(fileURLWithPath: path)) }
                NSApp.terminate(nil)
            }
        }
        let update: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.benchmarkLine += 1
            self.screenLyrics = ("When the night turns quiet I can hear every distant voice calling me back home \(self.benchmarkLine % 2)", 8)
            self.updateMarqueeText()
            if mode == "static" { (self.marqueeLabel as? NativeMarqueeView)?.setPlaybackPaused(true) }
        }
        update()
        let timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in update() }
        // Keep the trace termination timer separate; the run loop retains both timers.
        if ProcessInfo.processInfo.environment["LYRICSX_BENCH_TRACE"] == nil { benchmarkTimer = timer }
    }
    #endif

    private func setupStatusItemMenu() {
        iconStatusItem?.menu = statusBarMenu
        lyricStatusItem?.menu = statusBarMenu
    }
}

// MARK: - Status Item Visibility

extension NSStatusItem {
    fileprivate var isVisibe: Bool {
        guard let buttonFrame = button?.frame,
              let frame = button?.window?.convertToScreen(buttonFrame) else {
            return false
        }

        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }
        let carbonPoint = CGPoint(x: point.x, y: screen.frame.height - point.y - 1)

        guard let element = try? AXUIElement.systemWide().element(at: carbonPoint),
              let pid = try? element.pid() else {
            return false
        }

        return getpid() == pid
    }
}

extension String {
    fileprivate func components(options: String.EnumerationOptions) -> [String] {
        var components: [String] = []
        let range = Range(uncheckedBounds: (startIndex, endIndex))
        enumerateSubstrings(in: range, options: options) { _, _, range, _ in
            components.append(String(self[range]))
        }
        return components
    }
}

extension Array {
    subscript(safe safeIndex: Int) -> Element? {
        if safeIndex >= 0, safeIndex < count {
            return self[safeIndex]
        } else {
            return nil
        }
    }
}
