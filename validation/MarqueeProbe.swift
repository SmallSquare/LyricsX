import AppKit
import Darwin
import QuartzCore

@main
struct MarqueeProbe {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var label: NSView!
    private var timers: [Timer] = []
    private var started = CACurrentMediaTime()
    private var startCPU: Double = 0
    private var line = 0
    private var mode = "native"
    private var scenario = "scroll"
    private var fps: Double = 30
    private let lineDuration: Double = 10
    private var duration: Double = 40
    private var frameTrace: FrameCadenceTrace?

    private func argument(_ name: String, default fallback: String) -> String {
        guard let idx = CommandLine.arguments.firstIndex(of: name), idx + 1 < CommandLine.arguments.count else { return fallback }
        return CommandLine.arguments[idx + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        mode = argument("--renderer", default: "native")
        scenario = argument("--scenario", default: "scroll")
        fps = Double(argument("--fps", default: "30")) ?? 30
        duration = Double(argument("--duration", default: "40")) ?? 40
        statusItem = NSStatusBar.system.statusItem(withLength: 183)
        let frame = NSRect(x: 0, y: 0, width: 183, height: 22)
        if mode == "original" {
            label = MarqueeLabel(frame: frame)
        } else {
            let view = NativeMarqueeView(frame: frame)
            view.frameRate = fps
            label = view
        }
        statusItem.button?.addSubview(label)
        let menu = NSMenu()
        menu.addItem(withTitle: "Renderer: \(mode), \(scenario), \(fps) fps", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Quit test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        updateLyric()
        if CommandLine.arguments.contains("--trace-cadence") {
            frameTrace = FrameCadenceTrace(view: label)
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: lineDuration, repeats: true) { [weak self] _ in self?.updateLyric() })
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.report() })
        timers.append(Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in NSApp.terminate(nil) })
        started = CACurrentMediaTime()
        startCPU = cpuTime()
        printJSON(["event": "start", "pid": getpid(), "renderer": mode, "scenario": scenario,
                   "fps": fps, "displays": NSScreen.screens.map { ["width": $0.frame.width, "height": $0.frame.height, "scale": $0.backingScaleFactor] }])
    }

    private func updateLyric() {
        line += 1
        let value = scenario == "static" ? "歌词静态对照" : "原生菜单栏平滑滚动验证：长歌词在多个屏幕上保持位置和同步 \(line % 2)"
        if let label = label as? MarqueeLabel {
            label.setStringValue(value, lineDisplayTime: lineDuration)
        } else if let label = label as? NativeMarqueeView {
            label.setStringValue(value, lineDisplayTime: lineDuration)
        }
    }

    private func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private func report() {
        let elapsed = CACurrentMediaTime() - started
        var data: [String: Any] = ["event": "sample", "renderer": mode, "scenario": scenario,
                                   "elapsed": elapsed, "cpu_seconds": cpuTime() - startCPU,
                                   "cpu_percent_mean": 100 * (cpuTime() - startCPU) / elapsed]
        if let view = label as? NativeMarqueeView {
            data["draw_count"] = view.drawCount
            data["bitmap_builds"] = view.bitmapBuildCount
            data["offset"] = view.currentTextOffset
            data["timer_active"] = view.isAnimating
        }
        printJSON(data)
    }

    func applicationWillTerminate(_ notification: Notification) {
        frameTrace?.finish()
        report()
    }

    private func printJSON(_ object: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
            fflush(stdout)
        }
    }
}

/// Legacy diagnostic only. Final study uses full-app callbacks without this polling timer.
final class FrameCadenceTrace {
    private weak var view: NSView?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private let start = CACurrentMediaTime()
    private var samples: [[String: Double]] = []
    private var changes: [Double] = []

    init(view: NSView) {
        self.view = view
        if let field = view.subviews.first as? NSTextField {
            field.postsFrameChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                               object: field, queue: nil) { [weak self] _ in
                guard let self = self else { return }
                self.changes.append(CACurrentMediaTime() - self.start)
            }
        }
        let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self] _ in self?.sample() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sample() {
        guard let view = view else { return }
        let field = view.subviews.first as? NSTextField
        var record: [String: Double] = ["t": CACurrentMediaTime() - start]
        if let native = view as? NativeMarqueeView {
            record["offset"] = Double(native.currentTextOffset)
        } else if let field = field {
            record["model_x"] = Double(field.frame.origin.x)
            if let presentation = field.layer?.presentation() {
                record["presentation_x"] = Double(presentation.frame.origin.x)
            }
        }
        samples.append(record)
    }

    func finish() {
        timer?.invalidate()
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        let record: [String: Any] = ["event": "cadence_trace", "samples": samples,
                                    "frame_notifications": changes,
                                    "maximum_screen_fps": NSScreen.screens.map { $0.maximumFramesPerSecond }]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let output = String(data: data, encoding: .utf8) {
            print(output)
            fflush(stdout)
        }
    }
}
