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
internal compositing behavior. Later live tests showed that `transient` alone did
not fix active desktop lyrics. Disabling screenshot hiding changed the actual
window sharing state from 0 to 1, but the user still observed black previews.
Screenshot exclusion alone is therefore not a sufficient explanation.

## Fix

- Only order the desktop window in when desktop lyrics are enabled and the
  displayed lines contain non-whitespace content.
- Order the entire window out when disabled or cleared, including at startup.
- Route explicit `showWindow` calls through the same visibility condition.
- Use `transient` instead of `stationary`, so AppKit hides active desktop lyrics
  in Mission Control. Keep `canJoinAllSpaces` and exclude the utility from window
  cycling.
- Size the existing desktop window to the visible lyric lines and their padding,
  instead of the entire screen. Recalculate after lyric, font, annotation or
  orientation changes. Clamp it to the available screen area and preserve the
  relative placement preferences when dragging between displays.
- Preserve the screenshot-hiding preference. Menu-bar lyrics remain inside their
  native NSStatusItem, with no manual placement or additional windows.

The SDK documents `transient` as hidden by Exposé and `stationary` as remaining
visible. This uses that window behavior rather than private Mission Control
notifications or polling.

## Validation and limits

Run `python3 validation/check-desktop-window-visibility.py` on macOS with Xcode.
It extracts the production visibility methods and collection behavior into a
real NSWindow harness; only the lyric view and settings accessor are substitutes.
Twenty-one checks cover disabled startup, incoming lyrics, enable/disable, empty
content, translation-only content, clear/resume, explicit show calls, collection
behavior, preservation of screenshot exclusion, compact sizing, edge bounds,
negative screen origins and invalid geometry.

Release compilation and strict local ad-hoc signature validation passed. The
user accepted preview recovery with desktop lyrics disabled. After content sizing,
a real two-line lyric was visible in a 456 × 92 pt window rather than a
1800 × 1130 pt window. The user then supplied a screenshot confirming both
full-screen application previews were restored with desktop lyrics enabled.
The user also re-enabled screenshot hiding and confirmed the previews remained
normal with active desktop lyrics. These acceptance results concern Mission
Control previews, not whether every capture method omits lyrics. The OS
compositor's internal failure mechanism has not been established.

The legacy screenshot exclusion flag is not a reliable capture prevention
promise on modern macOS. Apple documents `NSWindow.SharingType.none` as a legacy
constant that should not be used to prevent capture. This fix does not claim
new screenshot privacy guarantees. See:
https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none

Old macOS and disruptive power tests were not performed.
