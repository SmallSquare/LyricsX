import AppKit
import Combine
import MusicPlayer

private final class Candidate: MusicPlayerProtocol {
    var name: MusicPlayerName? { nil }
    @Published var currentTrack: MusicTrack?
    @Published var playbackState: PlaybackState = .stopped
    var playbackTime: TimeInterval = 0
    let objectWillChange = ObservableObjectPublisher()
    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> { $currentTrack.eraseToAnyPublisher() }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var updates = 0
    var commands: [String] = []
    func set(_ state: PlaybackState, track: String? = "track") {
        objectWillChange.send()
        playbackState = state
        currentTrack = track.map { MusicTrack(id: $0, title: $0, album: nil, artist: nil) }
    }
    func resume() { commands.append("resume") }
    func pause() { commands.append("pause") }
    func skipToNextItem() { commands.append("next") }
    func skipToPreviousItem() { commands.append("previous") }
    func updatePlayerState() { updates += 1 }
}

@main enum AutomaticPlayerProbe {
    static func main() {
        let local = Candidate(), phone = Candidate()
        let automatic = AutomaticPlayer(players: [local, phone])
        var checks = 0
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1; print("PASS: \(message)")
        }
        check(automatic.designatedPlayer == nil, "no source when every candidate is stopped")
        phone.set(.playing(time: 1), track: "phone"); pump()
        check(automatic.designatedPlayer === phone, "phone is selected from idle")
        check(automatic.currentTrack?.id == "phone", "phone metadata is forwarded")
        automatic.skipToNextItem()
        check(phone.commands == ["next"] && local.commands.isEmpty, "commands route only to selected phone")
        local.set(.playing(time: 2), track: "local"); pump()
        check(automatic.designatedPlayer === phone, "background playback does not steal a playing source")
        phone.set(.paused(time: 1), track: "phone"); pump()
        check(automatic.designatedPlayer === local, "phone pause switches to playing local source")
        local.set(.paused(time: 2), track: "local"); pump()
        check(automatic.designatedPlayer === local, "paused source is retained when no other source is playing")
        phone.set(.playing(time: 3), track: "phone"); pump()
        check(automatic.designatedPlayer === phone, "a nonselected phone can take over a paused local source")
        check(automatic.currentTrack?.id == "phone", "new selected song replaces old source metadata")
        phone.set(.stopped, track: nil); pump()
        check(automatic.designatedPlayer === local, "phone disconnect falls back to available paused local source")
        local.set(.stopped, track: nil); pump()
        check(automatic.designatedPlayer == nil && automatic.currentTrack == nil, "all sources stopping clears metadata")
        local.set(.paused(time: 0), track: nil); pump()
        check(automatic.designatedPlayer == nil, "empty paused candidate cannot displace real content")
        phone.set(.playing(time: 4), track: nil); pump()
        check(automatic.designatedPlayer === phone, "playing phone stays selected while new metadata is loading")
        phone.set(.playing(time: 4), track: "next phone song"); pump()
        check(automatic.currentTrack?.id == "next phone song", "late metadata from selected source is forwarded")
        automatic.refreshCandidates()
        check(local.updates == 1 && phone.updates == 1, "explicit refresh updates every candidate")
        let local2 = Candidate(), phone2 = Candidate()
        local2.set(.playing(time: 0)); phone2.set(.playing(time: 0))
        let both = AutomaticPlayer(players: [local2, phone2])
        check(both.designatedPlayer === local2, "initial simultaneous playback has deterministic local-first priority")
        local2.set(.stopped, track: nil); pump()
        check(both.designatedPlayer === phone2, "stopped local source falls back to playing phone")
        let onlyPhone = AutomaticPlayer(players: [phone2])
        check(onlyPhone.designatedPlayer === phone2, "phone works when no local system player is available")
        print("\(checks) automatic source checks passed")
    }
}
