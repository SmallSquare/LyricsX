import AppKit
import IOBluetooth
import MusicPlayer

private final class Wire: PhoneTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var coverPSM: UInt16? = 0x1009
    var sent: [Data] = []
    var addresses: [String] = []
    var disconnects = 0
    func connect(address: String) { addresses.append(address) }
    func disconnect() { disconnects += 1 }
    var acknowledgeCommands = true
    func send(_ data: Data) {
        sent.append(data)
        if acknowledgeCommands, data.count == 8, data[5] == 0x7c {
            var reply = data; reply[0] |= 2; reply[3] = 9
            onData?(reply)
        }
    }
    func command(_ pdu: UInt8, event: UInt8? = nil) -> Data? {
        sent.last { packet in let b = [UInt8](packet); return b.count >= 13 && b[9] == pdu && (event == nil || b[13] == event) }
    }
    func answer(_ command: Data, _ parameters: [UInt8], code: UInt8 = 0x0c, fragment: UInt8 = 0, pdu: UInt8? = nil) {
        let b = [UInt8](command)
        onData?(Data([b[0] | 2, 0x11, 0x0e, code, 0x48, 0, 0, 0x19, 0x58, pdu ?? b[9], fragment, UInt8(parameters.count >> 8), UInt8(parameters.count & 255)] + parameters))
    }
}

private final class ArtworkWire: PhoneArtworkTransport {
    var onReady: (() -> Void)?
    var onImage: ((String, Data) -> Void)?
    var onState: ((PhoneArtworkState) -> Void)?
    var endpoints: [UInt16?] = []
    var handles: [String] = []
    var sessionRestarts = 0
    func connect(address: String) {}
    func connect(address: String, psm: UInt16?) { endpoints.append(psm) }
    func fetch(handle: String) { handles.append(handle) }
    func restartSession() { sessionRestarts += 1 }
    func disconnect() {}
}


import Combine

private final class LocalCandidate: MusicPlayerProtocol {
    var name: MusicPlayerName? { nil }
    var currentTrack: MusicTrack? = MusicTrack(id: "unrelated-local", title: "Local paused song", album: nil, artist: nil)
    @Published var playbackState: PlaybackState = .paused(time: 42)
    let objectWillChange = ObservableObjectPublisher()
    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> { Just(currentTrack).eraseToAnyPublisher() }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var playbackTime: TimeInterval = 42
    func resume() { playbackState = .playing(time: 42) }
    func pause() { playbackState = .paused(time: 42) }
    func skipToNextItem() {} ; func skipToPreviousItem() {} ; func updatePlayerState() {}
}

@main enum PhoneTrackTransitionProbe {
    static func main() {
        _ = NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ message:String) {
            guard value else { fatalError(message) };checks += 1;print("PASS: \(message)")
        }
        func pump() { RunLoop.main.run(until:Date().addingTimeInterval(0.03)) }
        let suite="LyricsX.TransitionProbe." + UUID().uuidString
        let prefs=UserDefaults(suiteName:suite)!
        defer { prefs.removePersistentDomain(forName:suite) }
        let wire=Wire(); var now=Date()
        let phone=PhonePlayer(transport:wire,coverArt:ArtworkWire(),preferences:prefs,now:{now})
        let local=LocalCandidate()
        let playing:[UInt8]=[0,2,0xbf,0x20,0,0,0x30,0x39,1]
        func song(_ title:String)->[UInt8] { [1,0,0,0,1,0,106,0,UInt8(title.utf8.count)] + Array(title.utf8) }
        func settleStatus() {
            let first = wire.command(0x30)!
            wire.answer(first,playing)
            if let fresh = wire.command(0x30), fresh != first { wire.answer(fresh,playing) }
        }
        phone.connect(address:"00-00-00-00-00-01",name:"Fixture");wire.onOpen?()
        wire.answer(wire.command(0x20)!,song("A"));wire.answer(wire.command(0x30)!,playing)
        wire.answer(wire.command(0x10)!,[3,2,1,2])
        wire.answer(wire.command(0x31,event:1)!,[1,1],code:0x0f)
        wire.answer(wire.command(0x31,event:2)!,[2,0,0,0,0,0,0,0,1],code:0x0f)
        wire.answer(wire.command(0x30)!,playing)
        let auto=AutomaticPlayer(players:[local,phone],refreshInterval:0)
        let view=PlaybackMenuView(player:auto,loadArtwork:{_,_,done in done(nil)})
        view.isLoadingTrack={ (auto.designatedPlayer as? PhonePlayer)?.isLoadingTrack == true }
        view.canControlWithoutTrack={ (auto.designatedPlayer as? PhonePlayer)?.isConnected == true }
        view.beginTracking()
        var events:[String]=[]
        let c=auto.currentTrackWillChange.sink { events.append($0?.title ?? "<empty>") }
        pump()
        let next=view.subviews.compactMap{$0 as? NSButton}.first{$0.accessibilityLabel() == "Next Track"}!
        let previous=view.subviews.compactMap{$0 as? NSButton}.first{$0.accessibilityLabel() == "Previous Track"}!
        let beforeClick=wire.command(0x20)!
        func click(_ button: NSButton, operation: UInt8) {
            check(button.isEnabled, "menu transport button remains enabled")
            let before = wire.sent.count
            button.performClick(nil)
            let commands = wire.sent.dropFirst(before).filter { $0.count == 8 && $0[5] == 0x7c }
            check(commands.count == 2 && commands[0][6] == operation && commands[1][6] == operation | 0x80,
                  "native button click sends exactly one ordered press/release pair")
        }
        click(next, operation: 0x4b)
        pump()
        check(phone.currentTrack == nil && phone.isChangingTrack,"menu skip immediately clears lyrics and starts a bounded transition")
        check(auto.designatedPlayer === phone,"paused local song never takes selection during a phone skip")
        check(view.subviews.compactMap{$0 as? NSTextField}.contains{$0.stringValue == "Loading song…"},"menu shows loading instead of claiming playback stopped")
        wire.answer(beforeClick,song("Old cached response"));pump()
        check(phone.currentTrack == nil,"pre-command metadata reply cannot repopulate the menu")
        wire.answer(wire.command(0x20)!,song("A"));pump()
        check(phone.currentTrack == nil,"post-command reply still naming the old song is not shown again")
        wire.answer(wire.command(0x31,event:2)!,[2,0,0,0,0,0,0,0,2],code:0x0d);pump()
        wire.answer(wire.command(0x20)!,song("B"));pump()
        check(auto.designatedPlayer === phone && phone.currentTrack?.title == "B","new metadata can appear before the new playback clock without changing source")
        settleStatus();pump()
        check(!phone.isChangingTrack && events == ["A","<empty>","B"],"one skip produces only A, loading, B")
        // An already playing Mac source must not steal focus merely because
        // the selected phone temporarily has no clock during a skip.
        local.resume();auto.refreshCandidates();pump()
        check(auto.designatedPlayer === phone,"a second playing source does not steal a playing phone")
        click(previous, operation: 0x4c)
        pump()
        check(auto.designatedPlayer === phone,"phone transition stays stable even with another playing source")
        let stale=wire.command(0x20)!
        // Let UI subscriptions refresh between clicks: a direct sendAction
        // would bypass isEnabled and miss the actual disabled-button regression.
        for _ in 0..<3 { click(next, operation: 0x4b); pump() }
        click(previous, operation: 0x4c); pump()
        wire.answer(stale,song("Intermediate response"));pump()
        check(phone.currentTrack == nil,"rapid next/previous rejects an intermediate outstanding response")
        wire.answer(wire.command(0x20)!,song("C"));settleStatus();pump()
        check(phone.currentTrack?.title == "C" && auto.designatedPlayer === phone,"rapid skips settle on the latest requested track")
        phone.skipToNextItem();pump()
        wire.answer(wire.command(0x31,event:1)!,[1,2],code:0x0d);pump()
        check(!phone.isChangingTrack && auto.designatedPlayer === local,"a confirmed phone pause immediately allows a playing Mac source to take over")
        local.pause();auto.refreshCandidates();pump()
        check(auto.designatedPlayer === local,"both paused keeps the current selection")
        // Recover the phone, then drop all replies after a skip.
        wire.answer(wire.command(0x20)!,song("D"));settleStatus()
        auto.refreshCandidates();pump()
        check(auto.designatedPlayer === phone,"playing phone can take over a paused Mac source")
        phone.skipToNextItem();now=now.addingTimeInterval(2.1);phone.updatePlayerState();pump()
        check(!phone.isChangingTrack && auto.designatedPlayer === phone,"selection grace expires without falling back to unrelated paused content")
        now=now.addingTimeInterval(1.1);phone.updatePlayerState();pump()
        check(phone.isLoadingTrack && view.subviews.compactMap{$0 as? NSTextField}.contains{$0.stringValue == "Loading song…"},
              "after three seconds missing metadata still shows loading, not no music")
        check(next.isEnabled && previous.isEnabled,"connected phone remains controllable beyond the selection grace period")
        local.resume();auto.refreshCandidates();pump()
        check(auto.designatedPlayer === local,"a stalled transition cannot indefinitely block a playing source")
        // A response at 800ms is still valid; the old 500ms retry discarded it.
        local.pause();wire.answer(wire.command(0x20)!,song("E"));settleStatus()
        auto.refreshCandidates();pump()
        phone.skipToNextItem()
        let delayedMeta=wire.command(0x20)!, delayedStatus=wire.command(0x30)!
        now=now.addingTimeInterval(0.8);phone.updatePlayerState()
        check(wire.command(0x20) == delayedMeta && wire.command(0x30) == delayedStatus,"800ms does not expire a valid query")
        wire.answer(delayedMeta,song("F"));wire.answer(delayedStatus,playing);pump()
        check(phone.currentTrack?.title == "F" && !phone.isChangingTrack,"800ms responses publish without retry")
        phone.skipToNextItem()
        let lostMeta=wire.command(0x20)!, lostStatus=wire.command(0x30)!
        now=now.addingTimeInterval(2.1);phone.updatePlayerState()
        let retryMeta=wire.command(0x20)!, retryStatus=wire.command(0x30)!
        check(retryMeta != lostMeta && retryStatus != lostStatus,"true request timeout recovers with new transactions")
        wire.answer(lostMeta,song("Late discarded song"));wire.answer(lostStatus,playing)
        check(phone.currentTrack == nil,"expired response cannot replace current content")
        wire.answer(retryMeta,song("G"));wire.answer(retryStatus,playing);pump()
        check(phone.currentTrack?.title == "G","retry publishes the recovered song")
        // Restart the grace window on each explicit click, rather than letting
        // a second skip inherit the nearly expired first skip's deadline.
        click(next, operation: 0x4b);pump()
        now=now.addingTimeInterval(1.8)
        click(next, operation: 0x4b);pump()
        now=now.addingTimeInterval(0.4);phone.updatePlayerState();pump()
        check(phone.isChangingTrack,"each click renews source stability from the latest action")
        wire.answer(wire.command(0x20)!,[0]);pump()
        check(phone.isLoadingTrack && phone.currentTrack == nil,"transient empty metadata during playback retains loading")
        now=now.addingTimeInterval(1.1);phone.updatePlayerState()
        let stoppedQuery = wire.command(0x30)!
        wire.answer(stoppedQuery,Array(playing.dropLast())+[0])
        if let fresh=wire.command(0x30), fresh != stoppedQuery { wire.answer(fresh,Array(playing.dropLast())+[0]) }
        wire.answer(wire.command(0x20)!,[0]);pump()
        check(!phone.isLoadingTrack && phone.currentTrack == nil,"confirmed stop plus empty metadata resolves to no track")
        check(next.isEnabled,"an empty queue still permits commands while the phone is connected")
        phone.disconnect();pump()
        check(!phone.isChangingTrack && !phone.isLoadingTrack,"disconnect ends both selection grace and loading")
        check(!next.isEnabled && !previous.isEnabled,"disconnected empty source disables commands")
        let disconnectedCount=wire.sent.count
        next.performClick(nil)
        check(wire.sent.count == disconnectedCount,"disabled native button does not dispatch any command")
        view.endTracking();withExtendedLifetime(c) {}
        print("\(checks) integrated menu/phone/source checks passed")
    }
}
