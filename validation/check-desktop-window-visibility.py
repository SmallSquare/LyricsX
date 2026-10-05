"""Exercise production visibility methods with a real NSWindow, without song/network dependencies."""
from pathlib import Path
import subprocess
import re
root = Path(__file__).resolve().parents[1]
source = (root / 'LyricsX/Controller/KaraokeLyricsController.swift').read_text()
start = source.index('    override func showWindow(')
end = source.index('    private func updateWindowFrame(', start)
methods = source[start:end].replace('private func ', 'func ')
behavior = re.search(r'window.collectionBehavior = (\[[^\n]+\])', source).group(1)
assert 'contentView?.bind(.hidden' not in source
assert 'observeDefaults(key: .desktopLyricsEnabled' in source
folder = root / 'outputs/mission-control'
folder.mkdir(parents=True, exist_ok=True)
probe = '''import AppKit
struct Settings {
    enum Key { case desktopLyricsEnabled }
    var enabled = false
    subscript(_ key: Key) -> Bool { enabled }
}
var defaults = Settings()
final class LyricsViewStub {
    func displayLrc(_ first: String, secondLine: String) {}
}
final class Controller: NSWindowController {
    var lyricsView = LyricsViewStub()
    var hasDisplayedLyrics = false
METHODS
}
_ = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: true)
window.isReleasedWhenClosed = false
window.backgroundColor = .clear
window.isOpaque = false
window.sharingType = .none
window.collectionBehavior = BEHAVIOR
let controller = Controller(window: window)
var checks = 0
func check(_ value: Bool, _ message: String) {
    precondition(value, message)
    checks += 1
    print("PASS: " + message)
}
check(window.collectionBehavior.contains(.transient) && !window.collectionBehavior.contains(.stationary), "Mission Control uses system transient hiding instead of a stationary overlay")
check(window.collectionBehavior.contains(.canJoinAllSpaces), "desktop lyrics remain available across Spaces")
controller.displayLyrics("LyricsX")
controller.showWindow(nil)
check(!window.isVisible, "disabled startup never orders in the protected window")
controller.displayLyrics("new song")
check(!window.isVisible, "incoming lyrics cannot display a disabled window")
defaults.enabled = true
controller.updateWindowVisibility()
check(window.isVisible, "enabled lyrics can display")
defaults.enabled = false
controller.updateWindowVisibility()
check(!window.isVisible, "disable orders the whole window out immediately")
defaults.enabled = true
controller.displayLyrics("")
check(!window.isVisible, "empty lyrics stay out even when enabled")
controller.displayLyrics("   ", secondLine: "\\n")
check(!window.isVisible, "whitespace does not leave an invisible window")
controller.displayLyrics("", secondLine: "translation")
check(window.isVisible, "a nonempty second line can display")
controller.displayLyrics("")
check(!window.isVisible, "clearing a previously visible line removes its window")
controller.showWindow(nil)
check(!window.isVisible, "external showWindow cannot bypass empty content")
controller.displayLyrics("resumed")
check(window.isVisible, "new content restores the window after pause or clear")
check(window.sharingType == .none, "screenshot exclusion preference is preserved")
window.orderOut(nil)
print("\\(checks) desktop window checks passed")
'''.replace('METHODS', methods).replace('BEHAVIOR', behavior)
path = folder / 'VisibilityProbe.swift'
path.write_text(probe)
subprocess.run(['xcrun','swiftc','-module-cache-path',str(root/'.build/ModuleCache'),str(path),'-o',str(folder/'VisibilityProbe')],check=True)
subprocess.run([str(folder/'VisibilityProbe')],check=True)
