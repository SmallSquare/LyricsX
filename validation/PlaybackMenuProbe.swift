import AppKit
import Combine
import MusicPlayer

private final class ProbePlayer: MusicPlayerProtocol {
    var name: MusicPlayerName? = .appleMusic
    var currentTrack: MusicTrack? = MusicTrack(id: "probe", title: "Track", album: "Album", artist: "Artist", duration: 180)
    var playbackState: PlaybackState = .paused(time: 45)
    var playbackTime: TimeInterval = 45
    let objectWillChange = ObservableObjectPublisher()
    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> { Empty().eraseToAnyPublisher() }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> { Empty().eraseToAnyPublisher() }
    var commands: [String] = []
    func resume() { commands.append("play"); playbackState = .playing(time: playbackTime) }
    func pause() { commands.append("pause"); playbackState = .paused(time: playbackTime) }
    func skipToNextItem() { commands.append("next") }
    func skipToPreviousItem() { commands.append("previous") }
    func updatePlayerState() { commands.append("update") }
}

@main private enum PlaybackMenuProbe {
    static func main() {
        _ = NSApplication.shared
        let player = ProbePlayer()
        let view = PlaybackMenuView(player: player, loadArtwork: { _, _, done in done(nil) })
        let buttons = view.subviews.compactMap { $0 as? NSButton }.filter { !$0.isTransparent }
        let slider = view.subviews.compactMap { $0 as? NSSlider }.first!
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            count += 1
            print("PASS: \(name)")
        }
        func send(_ control: NSControl) {
            check(control.sendAction(control.action!, to: control.target), "control action delivered")
        }
        check(buttons.count == 3, "three playback commands")
        check(slider.isEnabled && slider.maxValue == 180 && slider.doubleValue == 45, "duration and elapsed position")
        view.beginTracking()
        check(view.isMenuOpen && player.commands.last == "update", "opening refreshes selected player")
        send(buttons[0]); check(player.commands.suffix(2) == ["previous", "update"], "previous routes to selected player")
        send(buttons[1]); check(player.commands.suffix(2) == ["play", "update"], "play routes to selected player")
        send(buttons[1]); check(player.commands.suffix(2) == ["pause", "update"], "pause routes to selected player")
        send(buttons[2]); check(player.commands.suffix(2) == ["next", "update"], "next routes to selected player")
        slider.doubleValue = 100
        send(slider)
        check(player.playbackTime == 100, "seek writes selected player's position")
        player.playbackState = .playing(time: 100)
        view.refresh()
        player.playbackTime = 110
        let trackingDeadline = Date().addingTimeInterval(1.15)
        while Date() < trackingDeadline {
            _ = RunLoop.main.run(mode: .eventTracking, before: trackingDeadline)
        }
        check(slider.doubleValue == 110, "open playing menu refreshes progress")
        view.endTracking()
        player.playbackTime = 120
        RunLoop.main.run(until: Date().addingTimeInterval(1.15))
        check(!view.isMenuOpen && slider.doubleValue == 110, "closed menu stops progress updates")
        player.playbackState = .paused(time: 120)
        view.beginTracking()
        player.playbackTime = 130
        RunLoop.main.run(until: Date().addingTimeInterval(1.15))
        check(slider.doubleValue == 120, "paused menu has no progress polling")
        player.currentTrack?.duration = .nan
        view.refresh()
        check(!slider.isEnabled, "unknown duration disables seeking")
        let before = player.playbackTime
        send(slider)
        check(player.playbackTime == before, "invalid duration cannot write playback position")
        player.currentTrack = nil
        player.playbackState = .stopped
        view.refresh()
        check(view.subviews.compactMap { $0 as? NSButton }.allSatisfy { !$0.isEnabled } && !slider.isEnabled, "empty player disables controls")
        check(PlaybackMenuView.timeString(3661) == "1:01:01", "hour formatting")
        check(PlaybackMenuView.timeString(.infinity) == "0:00" && PlaybackMenuView.timeString(-12) == "0:00", "invalid time formatting")
        view.endTracking()
        check(view.frame.size == NSSize(width: 320, height: 108), "compact card dimensions")
        var artworkCallbacks: [(NSImage?) -> Void] = []
        let artworkPlayer = ProbePlayer()
        let artworkView = PlaybackMenuView(player: artworkPlayer, loadArtwork: { _, _, done in artworkCallbacks.append(done) })
        let artworkImageView = artworkView.subviews.compactMap { $0 as? NSImageView }.first!
        artworkView.beginTracking()
        check(artworkCallbacks.count == 1, "missing artwork requests asynchronous fallback")
        artworkView.refresh()
        check(artworkCallbacks.count == 1, "refresh does not duplicate artwork request")
        let firstCover = NSImage(size: NSSize(width: 48, height: 48))
        artworkCallbacks[0](firstCover)
        check(artworkImageView.image === firstCover, "late artwork updates current song")
        artworkPlayer.currentTrack = MusicTrack(id: "next", title: "Next", album: "Album", artist: "Artist", duration: 180)
        artworkView.refresh()
        check(artworkCallbacks.count == 2 && artworkImageView.image !== firstCover, "song change clears previous artwork")
        artworkCallbacks[0](firstCover)
        check(artworkImageView.image !== firstCover, "stale artwork completion cannot overwrite next song")
        let secondCover = NSImage(size: NSSize(width: 48, height: 48))
        artworkCallbacks[1](secondCover)
        check(artworkImageView.image === secondCover, "next song receives its own artwork")
        let nativeCover = NSImage(size: NSSize(width: 48, height: 48))
        artworkPlayer.currentTrack?.artwork = nativeCover
        artworkView.refresh()
        check(artworkImageView.image === nativeCover, "native artwork takes priority over fallback")
        check(PlaybackArtworkLoader.matches(artworkPlayer.currentTrack!, title: " next ", artist: "ARTIST", album: "Album"), "metadata matching tolerates casing and surrounding spaces")
        check(!PlaybackArtworkLoader.matches(artworkPlayer.currentTrack!, title: "Next", artist: "Another artist", album: "Album"), "different artist is rejected")
        check(!PlaybackArtworkLoader.matches(artworkPlayer.currentTrack!, title: "Next", artist: "Artist", album: "Different album"), "different album is rejected")
        artworkView.layoutSubtreeIfNeeded()
        check(artworkImageView.frame.size == NSSize(width: 48, height: 48), "compact cover dimensions")
        check(artworkView.subviews.allSatisfy { artworkView.bounds.contains($0.frame) }, "all controls fit compact card")
        artworkView.endTracking()
        var openedPlayer: MusicPlayerProtocol?
        let linkPlayer = ProbePlayer()
        let linkView = PlaybackMenuView(player: linkPlayer, openPlayer: { openedPlayer = $0 }, loadArtwork: { _, _, done in done(nil) })
        linkView.layoutSubtreeIfNeeded()
        let hotspots = linkView.subviews.compactMap { $0 as? NSButton }.filter { $0.isTransparent }
        check(hotspots.count == 2, "cover and metadata have native click targets")
        send(hotspots[0])
        check(openedPlayer === linkPlayer && linkPlayer.commands.isEmpty, "cover opens selected player without playback commands")
        openedPlayer = nil
        send(hotspots[1])
        check(openedPlayer === linkPlayer, "song and artist area opens selected player")
        let playbackButtons = linkView.subviews.compactMap { $0 as? NSButton }.filter { !$0.isTransparent }
        check(hotspots.allSatisfy { hotspot in playbackButtons.allSatisfy { !hotspot.frame.intersects($0.frame) } }, "open-player hit areas do not overlap playback controls")
        let linkSlider = linkView.subviews.compactMap { $0 as? NSSlider }.first!
        check(playbackButtons.allSatisfy { !linkSlider.frame.intersects($0.frame) }, "playback controls do not overlap the seek slider")
        linkPlayer.currentTrack = nil
        linkView.refresh()
        check(hotspots.allSatisfy { !$0.isEnabled }, "no song disables open-player hit areas")
        linkPlayer.currentTrack = MusicTrack(id: "remote", title: "Phone Song", album: nil, artist: nil, duration: 180)
        linkView.canSeek = { false }; linkView.canOpenSource = { false }; linkView.canLoadArtwork = { false }
        linkView.refresh()
        let remoteSlider = linkView.subviews.compactMap { $0 as? NSSlider }.first!
        check(!remoteSlider.isEnabled && hotspots.allSatisfy { !$0.isEnabled }, "phone source disables unsupported seeking and app opening")
        let phoneTime = linkPlayer.playbackTime
        remoteSlider.doubleValue = 90
        send(remoteSlider)
        check(linkPlayer.playbackTime == phoneTime, "disabled remote seeking never sends a position write")
        print("\(count) checks passed")
    }
}
