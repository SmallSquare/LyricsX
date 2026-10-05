# Desktop lyrics and Mission Control previews

The desktop lyric controller used a screen-sized transparent window with
`canJoinAllSpaces` and `stationary`. Disabling desktop lyrics only hid its content
view; application startup still ordered the window in. When screenshot hiding
was enabled, that empty window retained `sharingType = .none`.

On the tested macOS 27.0.1 system, launching the app produced black full-screen
Space previews, and quitting restored them. The disabled desktop lyric window
was still on screen with screen-sized bounds and sharing state 0. Ordering it out
removed the window from the compositor, and the user confirmed preview recovery.
This identifies the window lifecycle trigger; it does not establish WindowServer's
internal handling of capture-excluded content.

## Fix

- Only order the desktop window in when desktop lyrics are enabled and the
  displayed lines contain non-whitespace content.
- Order the entire window out when disabled or cleared, including at startup.
- Route explicit `showWindow` calls through the same visibility condition.
- Use `transient` instead of `stationary`, so AppKit hides active desktop lyrics
  in Mission Control. Keep `canJoinAllSpaces` and exclude the utility from window
  cycling.
- Preserve the screenshot-hiding preference and existing lyric layout/dragging.
  Menu-bar lyrics remain inside their native NSStatusItem.

The SDK documents `transient` as hidden by Exposé and `stationary` as remaining
visible. This uses that window behavior rather than private Mission Control
notifications or polling.

## Validation and limits

Run `python3 validation/check-desktop-window-visibility.py` on macOS with Xcode.
It extracts the production visibility methods and collection behavior into a
real NSWindow harness; only the lyric view and settings accessor are substitutes.
Thirteen checks cover disabled startup, incoming lyrics, enable/disable, empty
content, translation-only content, clear/resume, explicit show calls, collection
behavior and preservation of screenshot exclusion.

Release compilation and strict local ad-hoc signature validation passed. The
user accepted preview recovery with desktop lyrics disabled. Active desktop
lyrics with screenshot hiding enabled still require end-to-end Mission Control
acceptance; collection-behavior checks alone are not visual acceptance.

The legacy screenshot exclusion flag is not a reliable capture prevention
promise on modern macOS. Apple documents `NSWindow.SharingType.none` as a legacy
constant that should not be used to prevent capture. This fix does not claim
new screenshot privacy guarantees. See:
https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none

Old macOS and disruptive power tests were not performed.
