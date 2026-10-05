# Menu bar rendering and desktop window fixes

This change targets the high CPU usage observed with animated menu bar lyric text on macOS 26 and later, including macOS 27. It adds a cached-bitmap rendering path and configurable scrolling update rates for those systems. It does not assert that every machine or song has the same performance gain.

On macOS 26 and later, LyricsX draws a cached lyric bitmap inside the existing `NSStatusItem.button` instead of animating an `NSTextField`. The system continues to own status-item placement. Earlier macOS versions keep the existing MarqueeLabel path.

Display preferences gain a Menu Bar Lyrics tab with Static, 24, 30, 60, 90 and 120 fps options. The default is 30. Selection persists and updates the renderer immediately. Static mode splits long lines into stationary pages within the line's duration, with no sliding or blank transition. CoreText chooses word boundaries and composed characters remain intact. Each page gets a minimum share of the available time, with the remainder weighted by character count; the final page remains until the next lyric. Pausing freezes the page. Switching between static and scrolling restarts the current line from its beginning. Changing the rate does not resume paused playback.

The renderer stops its timer for short or completed lines, paused playback, hidden or detached views, and sleeping screens. Identical lyric updates keep their cached image and scroll progress. Benchmark-only code is excluded unless `LYRICSX_BENCHMARK` is explicitly enabled.

## Desktop window lifecycle and Mission Control

Disabling desktop lyrics previously left its screen-sized, capture-excluded
window ordered in while hiding only the content. That window caused black
full-screen Space previews on the tested macOS 27.0.1 system. The controller now
orders disabled or empty desktop lyrics out, and uses AppKit's `transient`
behavior so active desktop lyrics hide in Mission Control. The screenshot-hiding
preference remains intact. Details, acceptance scope and reproduction are in
[desktop-window-lifecycle.md](desktop-window-lifecycle.md).

## Earlier macOS versions

- `#available(macOS 26, *)` selects the new renderer. Earlier systems still construct MarqueeLabel with the original frame and send lyric text and duration through its existing `setStringValue` method.
- New scrolling-rate and playback-pause handlers only apply to `NativeMarqueeView`; they do not change legacy MarqueeLabel animation. The new default preference is not applied to the legacy renderer.
- The Menu Bar Lyrics preferences tab is visible on earlier systems, but its selector is disabled and displays "Requires macOS 26 or later."
- The application deployment target remains macOS 10.15. Keeping the legacy code path is a source-level compatibility safeguard; live regression testing on earlier macOS versions was not performed.

## Validation

- An arm64 Release build succeeded with cached dependencies and signing disabled during compilation. The standalone trial app passed local ad-hoc signature verification.
- `LifecycleProbe.swift` passed 24 checks, including static line changes, all selectable scrolling rates, pause/resume and status-item attachment lifecycle. Run the short lifecycle harness using the commands in `README.md`.
- `StaticPagingProbe.swift` passed 37 checks for complete text coverage, English word and emoji boundaries, stationary transitions, pause/resume, resizing and mode changes. Static pages use one-shot deadlines, not a frame-rate timer.
- The actual preferences window passed a Simplified Chinese dark-appearance layout check and selection of all six options. A UI-selected nondefault value of 24 fps survived closing/reopening preferences and quitting/restarting the app. The final preference was restored to 30 fps. Details are in `settings-ui-acceptance.md`.

The measured renderer and settings sources were validated against v1.8.9 (`0e077101a176ab9efc6b506074a52d5ab0217e75`). The contribution branch is based on upstream master `372997ccec5acf6d031ecd1ba11d0dbaaaea2d97`; the seven intervening commits only change `ExportOptions.plist` and `appcast.xml`, so the tested application sources are unchanged by that update.

## Limits and remaining checks

Fullscreen and multiple displays have not been accepted on this setup. Earlier macOS fallback behavior and other languages/appearances have not received an additional live check. The trial app is not notarized, and iCloud capabilities were not validated.

The controlled full-app long-line samples show about 13.85% LyricsX CPU at 30 updates per second versus 36.49% for the existing animator path on this machine; 100% CPU means one core. These observations do not establish whole-Mac energy savings. Historical static-mode measurements predate stationary pagination and do not measure its cost. Position-update callbacks are not panel presentation FPS. System-component CPU and chip-only power samples have background/folding interference, and reliable whole-Mac power and pre-macOS-26 measurements remain unknown.

Raw sampling, build outputs, screenshots, private chat history, migration records and machine-specific collection scripts remain local. The source branch includes standalone validation harnesses and offline analysis/plotting helpers. Long power tests and old-OS testing were cancelled and were not repeated for these commits.
