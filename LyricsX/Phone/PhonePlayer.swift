import AppKit
import Combine
import MusicPlayer
import ImageIO

/// An AVRCP source: only control/metadata traffic is requested, never an audio profile.
final class PhonePlayer: ObservableObject, MusicPlayerProtocol {
    static let shared = PhonePlayer()
    static let preferenceIndex = 5
    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var playbackState: PlaybackState = .stopped
    @Published private(set) var statusMessage = NSLocalizedString("Choose a paired phone to connect.", comment: "Phone source")
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var artworkState: PhoneArtworkState = .unavailable
    private let transport: PhoneTransport
    private let coverArt: PhoneArtworkTransport
    private let preferences: UserDefaults
    private let now: () -> Date
    private var active = false
    private var reconnectSuppressed = false
    private var pollTimer: Timer?
    private var retryTimer: Timer?
    private var assembler = AVCTPAssembler()
    private var continuation = Data()
    private var continuationEpoch = 0
    private var epoch = 0
    private var label: UInt8 = 0
    private struct Pending { let pdu: UInt8; let event: UInt8?; let epoch: Int; var expires: Date?; var coverRefresh = false }
    private var pending: [UInt8: Pending] = [:]
    private var lastStatusResponse = Date.distantPast
    private var lastPoll = Date.distantPast
    private var lastStatusPoll = Date.distantPast
    private var knownDuration: TimeInterval?
    private var lastRemotePosition: TimeInterval?
    private var lastMetadata = Date.distantPast
    private var remoteState: UInt8 = 0
    private var retryDelay: TimeInterval = 3
    private var capabilitiesKnown = false
    private var capabilityAttemptsRemaining = 3
    private var capabilityRetryAfter = Date.distantPast
    private var supportedEvents = Set<UInt8>()
    private var registeredEvents = Set<UInt8>()
    private var notificationRetryAfter: [UInt8: Date] = [:]
    private var lastPositionNotification = Date.distantPast
    private static let observedEvents: [UInt8] = [1, 2, 5, 9, 10, 11, 12]
    private var metadata: [UInt32: String] = [:]
    private var artwork: NSImage?
    private var requestedHandle: String?
    private var coverMetadataRefreshPending = false
    private var coverSessionWaiting = false
    private var coverMetadataRetries = 0

    var name: MusicPlayerName? { nil }
    var savedAddress: String? { preferences.string(forKey: "PhoneBluetoothAddress") }
    var deviceName: String { preferences.string(forKey: "PhoneBluetoothName") ?? NSLocalizedString("Phone", comment: "Phone source") }
    var autoReconnect: Bool {
        get { preferences.object(forKey: "PhoneAutoReconnect") as? Bool ?? true }
        set { preferences.set(newValue, forKey: "PhoneAutoReconnect"); if !newValue { retryTimer?.invalidate(); retryTimer = nil } }
    }
    // Duration and artwork updates refresh the menu via objectWillChange; they
    // must not cancel/restart the existing song's lyric search.
    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> { $currentTrack.removeDuplicates().eraseToAnyPublisher() }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var playbackTime: TimeInterval {
        get { max(0, playbackState.time) }
        set { /* AVRCP has no interoperable absolute-position seek command. */ }
    }
    init(transport: PhoneTransport = PhoneBluetoothTransport(), coverArt: PhoneArtworkTransport? = nil, preferences: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        let coverArt = coverArt ?? PhoneCoverArt()
        self.transport = transport; self.coverArt = coverArt; self.preferences = preferences; self.now = now
        transport.onOpen = { [weak self] in self?.onMain { $0.opened() } }
        transport.onData = { [weak self] data in self?.onMain { $0.receive(data) } }
        transport.onStatus = { [weak self] message in self?.onMain { $0.statusMessage = message } }
        transport.onClose = { [weak self] message in self?.onMain { $0.closed(message) } }
        coverArt.onReady = { [weak self] in self?.onMain { player in
            player.coverSessionWaiting = false
            player.requestedHandle = nil
            player.artwork = nil; player.metadata[8] = nil; player.rebuildTrack()
            // An older metadata request may still be in flight. Keep this demand
            // until a new request is actually sent after OBEX becomes ready.
            player.coverMetadataRefreshPending = true
            player.coverMetadataRetries = 2
            player.lastMetadata = .distantPast; player.requestMetadata()
        } }
        coverArt.onState = { [weak self] state in self?.onMain { $0.artworkState = state } }
        coverArt.onImage = { [weak self] handle, data in self?.onMain { player in
            guard player.isConnected, !player.coverSessionWaiting, player.requestedHandle == handle, player.metadata[8] == handle,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, width > 0, width <= 512,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0, height <= 512,
                  let image = NSImage(data: data) else { return }
            player.artwork = image; player.artworkState = .loaded; player.rebuildTrack()
        } }
    }
    deinit { pollTimer?.invalidate(); retryTimer?.invalidate(); transport.disconnect(); coverArt.disconnect() }
    func setActive(_ value: Bool) {
        onMain { player in
            guard player.active != value else { return }
            player.active = value
            if value {
                player.reconnectSuppressed = false
                if let address = player.savedAddress { player.connect(address: address, name: player.deviceName) }
            } else { player.disconnect() }
        }
    }
    func remember(address: String, name: String) {
        preferences.set(address, forKey: "PhoneBluetoothAddress")
        preferences.set(name, forKey: "PhoneBluetoothName")
    }
    func connect(address: String, name: String) {
        onMain { player in
            player.reset()
            player.transport.disconnect()
            player.remember(address: address, name: name)
            player.reconnectSuppressed = false
            player.isConnecting = true
            player.statusMessage = NSLocalizedString("Connecting to phone…", comment: "Phone source")
            player.transport.connect(address: address)
        }
    }
    func disconnect() {
        onMain { player in
            player.reconnectSuppressed = true
            player.reset(); player.transport.disconnect()
            player.statusMessage = NSLocalizedString("Phone disconnected.", comment: "Phone source")
        }
    }
    private func reset() {
        pollTimer?.invalidate(); pollTimer = nil
        retryTimer?.invalidate(); retryTimer = nil
        pending.removeAll(); assembler.reset(); continuation.removeAll(); epoch += 1
        supportedEvents.removeAll(); registeredEvents.removeAll(); notificationRetryAfter.removeAll()
        capabilitiesKnown = false; capabilityAttemptsRemaining = 3; capabilityRetryAfter = .distantPast
        lastPositionNotification = .distantPast
        metadata.removeAll(); lastMetadata = .distantPast
        coverArt.disconnect(); artwork = nil; requestedHandle = nil
        coverMetadataRefreshPending = false
        coverMetadataRetries = 0
        coverSessionWaiting = false
        knownDuration = nil; lastRemotePosition = nil; lastPoll = .distantPast; lastStatusPoll = .distantPast
        isConnected = false; isConnecting = false; remoteState = 0
        currentTrack = nil; playbackState = .stopped
    }
    private func opened() {
        isConnecting = false; isConnected = true
        statusMessage = NSLocalizedString("Checking phone playback information…", comment: "Phone source")
        lastStatusResponse = now()
        requestCapabilities()
        poll()
        if let address = savedAddress { coverArt.connect(address: address, psm: transport.coverPSM) }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
    private func closed(_ message: String) {
        trace("channel closed: " + message)
        reset(); statusMessage = message
        guard active, !reconnectSuppressed, autoReconnect, savedAddress != nil else { return }
        let timer = Timer(timeInterval: retryDelay, repeats: false) { [weak self] _ in
            guard let self = self, let address = self.savedAddress, self.active, !self.reconnectSuppressed else { return }
            self.connect(address: address, name: self.deviceName)
        }
        retryDelay = min(30, retryDelay * 2)
        retryTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func fail(_ message: String) { transport.disconnect(); closed(message) }
    func updatePlayerState() { onMain { $0.poll() } }
    private func poll() {
        guard isConnected else { return }
        let timestamp = now()
        guard timestamp.timeIntervalSince(lastPoll) >= 0.18 else { return }
        lastPoll = timestamp
        for transaction in pending.values where transaction.expires.map({ $0 <= timestamp }) ?? false {
            if transaction.coverRefresh, coverMetadataRetries > 0 {
                coverMetadataRetries -= 1; coverMetadataRefreshPending = true
            }
            if transaction.pdu == 0x31, let event = transaction.event {
                registeredEvents.remove(event)
                notificationRetryAfter[event] = timestamp.addingTimeInterval(3)
                trace("notification registration timeout event=" + String(event))
            }
        }
        pending = pending.filter { $0.value.expires.map { $0 > timestamp } ?? true }
        requestCapabilities()
        let needsStatus = currentTrack == nil || !registeredEvents.contains(1)
            || ([UInt8(1), 3, 4].contains(remoteState) && (!registeredEvents.contains(5)
                || timestamp.timeIntervalSince(lastPositionNotification) > 3))
        if needsStatus, timestamp.timeIntervalSince(lastStatusResponse) > 8 {
            fail(NSLocalizedString("The phone is not sharing playback information.", comment: "Phone source")); return
        }
        if needsStatus, timestamp.timeIntervalSince(lastStatusPoll) >= 0.9, request(pdu: 0x30) { lastStatusPoll = timestamp }
        for event in Self.observedEvents where supportedEvents.contains(event)
            && !registeredEvents.contains(event)
            && timestamp >= (notificationRetryAfter[event] ?? .distantPast) { register(event: event) }
        // Once the phone accepts track notifications, a steady song needs no
        // repeated metadata queries. Loading and failed registrations keep the
        // existing short fallback, so old lyrics never stand in for a new track.
        if (coverMetadataRefreshPending || !registeredEvents.contains(2) || currentTrack == nil), timestamp.timeIntervalSince(lastMetadata) >= 0.2 { requestMetadata() }
    }
    private func requestCapabilities() {
        guard !capabilitiesKnown, capabilityAttemptsRemaining > 0, now() >= capabilityRetryAfter else { return }
        if request(pdu: 0x10, parameters: [3]) {
            capabilityAttemptsRemaining -= 1
            capabilityRetryAfter = now().addingTimeInterval(3)
        }
    }
    private func nextLabel() -> UInt8? {
        for _ in 0..<16 {
            label = (label + 1) & 15
            if pending[label] == nil { return label }
        }
        return nil
    }
    @discardableResult private func request(pdu: UInt8, parameters: [UInt8] = [], event: UInt8? = nil, expected: UInt8? = nil, command: UInt8 = 1, coverRefresh: Bool = false) -> Bool {
        let expected = expected ?? pdu
        guard isConnected, !pending.values.contains(where: { $0.pdu == expected && $0.event == event }), let label = nextLabel() else { return false }
        pending[label] = Pending(pdu: expected, event: event, epoch: epoch, expires: now().addingTimeInterval(3), coverRefresh: coverRefresh)
        trace(String(format: "send pdu=%02x label=%d epoch=%d event=%d", pdu, label, epoch, event.map(Int.init) ?? -1))
        transport.send(AVRCPCodec.vendor(label: label, pdu: pdu, parameters: parameters, command: command))
        return true
    }
    private func requestMetadata() {
        if request(pdu: 0x20, parameters: Array(repeating: 0, count: 9), coverRefresh: coverMetadataRefreshPending) {
            lastMetadata = now(); coverMetadataRefreshPending = false
        }
    }
    private func register(event: UInt8) {
        request(pdu: 0x31, parameters: [event, 0, 0, 0, 1], event: event, command: 3)
    }
    private func receive(_ raw: Data) {
        guard isConnected else { return }
        // Decline commands for unsupported Target functionality; this endpoint is a Controller.
        if let reply = AVRCPCodec.controllerReply(raw) { transport.send(reply); return }
        guard let assembled = assembler.receive(raw) else { return }
        let avc = [UInt8](assembled)
        if avc.count == 8, avc[1...2] == [0x11, 0x0e], avc[4] == 0x48, avc[5] == 0x7c, avc[7] == 0,
           let transaction = pending[avc[0] >> 4], transaction.pdu == 0x7c, transaction.event == avc[6] {
            pending[avc[0] >> 4] = nil
            return
        }
        guard let response = AVRCPCodec.response(assembled),
              let transaction = pending[response.label], transaction.pdu == response.pdu, transaction.epoch == epoch else { return }
        pending[response.label] = nil
        defer {
            if response.pdu == 0x20, coverMetadataRefreshPending { requestMetadata() }
        }
        if response.pdu == 0x31 || !response.successful || PhoneDiagnostics.enabled {
            trace(String(format: "reply pdu=%02x code=%02x epoch=%d event=%d", response.pdu, response.code, epoch, transaction.event.map(Int.init) ?? -1))
        }
        guard response.successful else {
            if response.pdu == 0x10, response.code == 8 { capabilityAttemptsRemaining = 0 }
            if response.pdu == 0x31, let event = transaction.event {
                registeredEvents.remove(event)
                notificationRetryAfter[event] = now().addingTimeInterval(3)
            }
            if [0x20, 0x30].contains(response.pdu), response.code == 8 {
                fail(NSLocalizedString("The phone does not support song information and playback position.", comment: "Phone source"))
            } else if [0x20, 0x30].contains(response.pdu) {
                // A player can temporarily reject current-element requests while
                // replacing its queue item. Keep the control channel and retry;
                // the status watchdog still detects a genuinely unavailable service.
                if currentTrack != nil { invalidateTrack() }
            }
            return
        }
        var parameters = response.parameters
        if response.fragment != 0 {
            guard response.pdu == 0x20 else { return }
            if response.fragment == 1 { continuation = parameters; continuationEpoch = epoch }
            else {
                guard continuationEpoch == epoch, !continuation.isEmpty else { return }
                continuation.append(parameters)
            }
            guard continuation.count <= 65536 else { continuation.removeAll(); return }
            if response.fragment != 3 { request(pdu: 0x40, parameters: [0x20], expected: 0x20, command: 0, coverRefresh: transaction.coverRefresh); return }
            parameters = continuation; continuation.removeAll()
        }
        switch response.pdu {
        case 0x10:
            let b = [UInt8](parameters)
            if b.count >= 2, b[0] == 3, b.count == 2 + Int(b[1]) {
                capabilitiesKnown = true
                supportedEvents = Set(b.dropFirst(2))
                trace("supported notification events: " + supportedEvents.sorted().map(String.init).joined(separator: ","))
                for event in Self.observedEvents where supportedEvents.contains(event) { register(event: event) }
            }
        case 0x20:
            guard var values = AVRCPCodec.attributes(parameters) else { trace("invalid attribute response"); return }
            trace("attribute ids: " + values.keys.sorted().map(String.init).joined(separator: ","))
            // Handles from a request sent before the new OBEX session are not
            // eligible for that session; title/artist can still update normally.
            if coverMetadataRefreshPending || coverSessionWaiting { values[8] = nil }
            if !metadata.isEmpty, [UInt32(1), 2, 3].contains(where: { metadata[$0] != values[$0] }) {
                // Devices without track-change notifications are detected by polling.
                // Do not attach the previous song's duration/position to the new title.
                trace("track changed via metadata poll")
                invalidateTrack()
                request(pdu: 0x30)
            }
            metadata = values; rebuildTrack()
            if values[8] != requestedHandle {
                artwork = nil; requestedHandle = values[8]; rebuildTrack()
                if let handle = requestedHandle { coverArt.fetch(handle: handle) }
            }
        case 0x30:
            guard let status = AVRCPCodec.status(parameters) else { return }
            lastStatusResponse = now(); retryDelay = 3
            apply(status)
        case 0x31:
            let b = [UInt8](parameters)
            guard let event = b.first, event == transaction.event,
                  [0x0f, 0x0d].contains(response.code),
                  b.count == (event == 1 ? 2 : event == 2 ? 9 : event == 5 || event == 11 ? 5 : event == 12 ? 3 : event == 9 || event == 10 ? 1 : 0) else {
                if let event = transaction.event {
                    registeredEvents.remove(event); notificationRetryAfter[event] = now().addingTimeInterval(3)
                }
                return
            }
            registeredEvents.insert(event); notificationRetryAfter[event] = nil
            if response.code == 0x0f {
                var transaction = transaction; transaction.expires = nil
                pending[response.label] = transaction
            }
            // Renew a one-shot notification before fetching dependent content.
            if response.code == 0x0d { register(event: event) }
            if (event == 2 || event == 11), response.code == 0x0d {
                trace("track changed via notification")
                invalidateTrack()
                requestMetadata(); request(pdu: 0x30)
            } else if event == 1 {
                // Use the notification payload immediately rather than waiting
                // for an additional status round trip to pause/resume the UI.
                lastStatusResponse = now()
                apply(AVRCPCodec.Status(duration: knownDuration, position: lastRemotePosition == nil ? nil : playbackTime, state: b[1]))
                request(pdu: 0x30)
            } else if event == 5 {
                let value = b.dropFirst().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                lastPositionNotification = now(); lastStatusResponse = now()
                apply(AVRCPCodec.Status(duration: knownDuration, position: value == .max ? nil : Double(value) / 1000, state: remoteState))
            } else if response.code == 0x0d, event == 12 {
                // UIDs_CHANGED invalidates every image handle in the old OBEX
                // session, even if the next song reuses the same handle text.
                coverSessionWaiting = true
                artwork = nil; requestedHandle = nil; metadata[8] = nil; rebuildTrack()
                if artworkState != .unavailable { artworkState = .connecting }
                coverArt.restartSession()
                lastMetadata = .distantPast; requestMetadata()
            } else if response.code == 0x0d, event == 9 || event == 10 {
                lastMetadata = .distantPast; requestMetadata()
            }
        default: break
        }
    }
    private func invalidateTrack() {
        epoch += 1; continuation.removeAll(); metadata.removeAll(); knownDuration = nil; lastRemotePosition = nil
        pending = pending.filter { $0.value.pdu == 0x31 }
        // Keep persistent notification labels in the new track epoch.
        pending = pending.mapValues { Pending(pdu: $0.pdu, event: $0.event, epoch: epoch, expires: $0.expires) }
        currentTrack = nil; playbackState = .stopped; lastMetadata = .distantPast
        artwork = nil; requestedHandle = nil
        if artworkState == .loaded { artworkState = .ready }
    }
    private func trace(_ message: String) {
        PhoneDiagnostics.write(message)
#if LYRICSX_PHONE_DIAGNOSTICS
        NSLog("LyricsX Phone: %@", message)
#endif
    }
    private func rebuildTrack() {
        guard let title = metadata[1], !title.isEmpty else { currentTrack = nil; return }
        let rawDuration = metadata[7].flatMap(Double.init).map { $0 / 1000 }
        let duration = knownDuration ?? rawDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let id = [savedAddress ?? "", title, metadata[2] ?? "", metadata[3] ?? ""].joined(separator: "\u{1f}")
        let track = MusicTrack(id: "phone:" + id, title: title, album: metadata[3], artist: metadata[2], duration: duration, artwork: artwork)
        if currentTrack?.id != track.id || currentTrack?.duration != track.duration || currentTrack?.artwork !== track.artwork { currentTrack = track }
    }
    private func apply(_ status: AVRCPCodec.Status) {
        if currentTrack != nil, let previousDuration = knownDuration,
           let duration = status.duration, duration > 0, duration != previousDuration {
            // New duration is already a strong change signal. Clear stale content
            // before waiting for the metadata reply to identify the next song.
            invalidateTrack(); requestMetadata()
        } else if let previous = lastRemotePosition, let position = status.position, position < previous - 2 {
            lastMetadata = .distantPast; requestMetadata()
        }
        lastRemotePosition = status.position
        remoteState = status.state
        if let duration = status.duration, duration > 0 { knownDuration = duration }
        rebuildTrack()
        guard let position = status.position, status.state != 255 else {
            playbackState = .stopped
            statusMessage = NSLocalizedString("Connected, but playback position is unavailable.", comment: "Phone source"); return
        }
        let time = min(knownDuration ?? position, position)
        let state: PlaybackState
        switch status.state {
        case 1: state = .playing(time: time)
        case 2: state = .paused(time: time)
        case 3: state = .fastForwarding(time: time)
        case 4: state = .rewinding(time: time)
        default: state = .stopped
        }
        if !playbackState.approximateEqual(to: state, tolerate: 0.3) { playbackState = state }
        statusMessage = NSLocalizedString("Phone connected.", comment: "Phone source")
    }
    func resume() { command(0x44) }
    func pause() { command(0x46) }
    func playPause() { command(remoteState == 1 ? 0x46 : 0x44) }
    func skipToNextItem() { command(0x4b) }
    func skipToPreviousItem() { command(0x4c) }
    private func command(_ operation: UInt8) {
        onMain { player in
            guard player.isConnected, player.pending.count <= 14 else { return }
            for released in [false, true] {
                guard let label = player.nextLabel() else { return }
                player.pending[label] = Pending(pdu: 0x7c, event: operation | (released ? 0x80 : 0), epoch: player.epoch, expires: player.now().addingTimeInterval(3))
                player.transport.send(AVRCPCodec.passThrough(label: label, operation: operation, released: released))
            }
            player.request(pdu: 0x30)
            if operation == 0x4b || operation == 0x4c { player.lastMetadata = .distantPast; player.requestMetadata() }
        }
    }
    private func onMain(_ action: @escaping (PhonePlayer) -> Void) {
        if Thread.isMainThread { action(self) }
        else { DispatchQueue.main.async { [weak self] in if let self = self { action(self) } } }
    }
}
