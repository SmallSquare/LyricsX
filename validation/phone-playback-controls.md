# Phone source and playback menu (experimental)

Branch: `codex/phone-source-playback-controls`, based on the macOS 26+ native
menu-bar rendering fix at `1f6755b`.

## Behavior

- A compact 320 × 108 pt playback card lives inside the existing native status
  menu, with 48 pt artwork, track details, source, transport controls and time.
  Local player artwork can be loaded asynchronously; artwork and metadata can
  open the corresponding local player. The progress timer runs only while the
  menu is open and playback is active.
- A fixed Bluetooth phone source uses AVRCP metadata, playback status and
  transport commands. It selects an already paired device and does not request
  A2DP audio routing. Changing source disables the phone connection.
- Accepted track/state/position notifications replace steady polling where
  available. Missing subscriptions and loading states use bounded fallback
  requests; a 250 ms metadata timer target is not an end-to-end latency promise.
- Song changes invalidate old metadata, cover handles and lyric searches. Loading
  shows a placeholder instead of retaining lyrics or images from the old song.
- Native Bluetooth inventory, media and cover work runs in supervised child
  processes. Length-limited IPC, heartbeats, connection deadlines, bounded
  retries and process termination isolate blocked native calls from the UI.
- Phone artwork has a small Bluetooth phone badge, also over the placeholder.
  Phone absolute seeking and opening a local player are disabled. Phone covers
  are only accepted through Bluetooth; no external artwork lookup is used.
- The About panel displays the bundle version literally, so local `.dev` version
  suffixes do not trigger a semantic-version parsing precondition failure.

## Compatibility and remaining limits

This is an experimental feature branch, not a claim of compatibility with every
phone. Live iPhone metadata, lyric synchronization and song changes were observed,
and the user confirmed correct lyrics and improved switching speed. Audio output
coexistence has not received separate end-to-end acceptance.

**Bluetooth artwork has not been obtained on the tested iPhone/Mac combination.**
The current on-wire target record advertised AVRCP 1.5, features `0x00d1`, and no
Cover Art PSM. The requested local controller declaration is 1.6, but the system
reuses its built-in 1.5 controller record. Causation between those observations
has not been established; they do not prove that iPhones generally lack Cover Art.
The OBEX/BIP implementation and reconnect lifecycle have offline coverage, not
successful end-to-end image-transfer evidence. A placeholder is expected.

On the tested macOS 27.0.1 runtime, public targeted SDP discovery did not produce
fresh wire queries and workers lacked some per-peer callbacks. The implementation
uses bounded SDP requests and feature-detected **undocumented selectors** to
install only missing callbacks within the worker. This compatibility path has
not been validated on other macOS versions. It does not modify the Bluetooth
daemon, remove system SDP records, reset pairings or change audio output.

## Validation

2026-10-04: 110 protocol/player checks, 19 SDP checks, 24 worker isolation checks
and 45 playback menu checks passed (198 total). Worker timer callbacks check UI
responsiveness during synthetic child failures; they do not measure screen FPS
or energy consumption. Release arm64 compilation and strict ad-hoc signature
verification passed. Dark/light badge renderings and the preference window were
checked; the corrected About action has not received a separate live UI click
acceptance. Old-macOS and disruptive power tests were not repeated.

The following standalone probes run on macOS with Xcode. Resolve the project's
locked packages into `.build/SourcePackages` first. The lightweight test module
uses the actual MusicPlayer protocol and model sources, not replacement types.
Probes use synthetic data and do not require a phone connection.

```sh
mkdir -p outputs/playback-probe .build/ModuleCache
music=.build/SourcePackages/checkouts/MusicPlayer/Sources/MusicPlayer
xcrun swiftc -emit-library -emit-module -module-name MusicPlayer \
  -module-cache-path .build/ModuleCache \
  "$music/MusicPlayer.swift" "$music/MusicTrack.swift" \
  "$music/PlaybackState.swift" "$music/PlayerName.swift" \
  "$music/Utilities/Typealias.swift" \
  -o outputs/playback-probe/libMusicPlayer.dylib \
  -emit-module-path outputs/playback-probe/MusicPlayer.swiftmodule
xcrun swiftc -module-cache-path .build/ModuleCache \
  -I outputs/playback-probe -L outputs/playback-probe -lMusicPlayer \
  -Xlinker -rpath -Xlinker '@executable_path' \
  LyricsX/Phone/*.swift validation/PhonePlayerProbe.swift \
  -o outputs/playback-probe/PhonePlayerProbe
outputs/playback-probe/PhonePlayerProbe
xcrun swiftc -module-cache-path .build/ModuleCache \
  -I outputs/playback-probe -L outputs/playback-probe -lMusicPlayer \
  -Xlinker -rpath -Xlinker '@executable_path' \
  LyricsX/Controller/PlaybackArtworkLoader.swift \
  LyricsX/Controller/PlaybackMenuView.swift validation/PlaybackMenuProbe.swift \
  -o outputs/playback-probe/PlaybackMenuProbe
outputs/playback-probe/PlaybackMenuProbe
xcrun swiftc -module-cache-path .build/ModuleCache \
  LyricsX/Phone/PhoneServiceDiscovery.swift validation/PhoneServiceDiscoveryProbe.swift \
  -o outputs/playback-probe/PhoneServiceDiscoveryProbe
outputs/playback-probe/PhoneServiceDiscoveryProbe
for probe in PhoneWorkerFaultFixture PhoneWorkerIsolationProbe; do
  xcrun swiftc -module-cache-path .build/ModuleCache \
    LyricsX/Phone/PhoneServiceDiscovery.swift LyricsX/Phone/PhoneCoverArt.swift \
    LyricsX/Phone/PhoneWorkerIPC.swift "validation/$probe.swift" \
    -o "outputs/playback-probe/$probe"
done
outputs/playback-probe/PhoneWorkerIsolationProbe outputs/playback-probe/PhoneWorkerFaultFixture
```

Build logs, packet captures, device identifiers, installed app backups and local
handoff records are deliberately kept out of the source commit. Dev naming and
ad-hoc signing are packaging choices; the source bundle ID remains unchanged.
