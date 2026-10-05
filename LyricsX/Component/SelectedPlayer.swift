import Foundation
import MusicPlayer
import GenericID
import Combine

extension MusicPlayers {
    final class Selected: Agent {
        static let shared = MusicPlayers.Selected()

        private var defaultsObservation: DefaultsObservation?

        private var manualUpdateObservation: AnyCancellable?

        var manualUpdateInterval: TimeInterval = 1.0 {
            didSet {
                scheduleManualUpdate()
            }
        }

        override init() {
            super.init()
            selectPlayer()
            scheduleManualUpdate()
            self.defaultsObservation = defaults.observe(keys: [.preferredPlayerIndex, .useSystemWideNowPlaying, .systemWideNowPlayingAppList]) { [weak self] in
                self?.selectPlayer()
            }
            self.manualUpdateObservation = playbackStateWillChange.sink { [weak self] state in
                if state.isPlaying {
                    self?.scheduleManualUpdate()
                } else {
                    self?.scheduleCanceller?.cancel()
                }
            }
        }

        private func selectPlayer() {
            let idx = defaults[.preferredPlayerIndex]
            PhonePlayer.shared.setActive(idx == -1 || idx == PhonePlayer.preferenceIndex)
            if idx == PhonePlayer.preferenceIndex {
                designatedPlayer = PhonePlayer.shared
            } else if idx == -1 {
                var players: [MusicPlayerProtocol]
                if defaults[.useSystemWideNowPlaying] {
                    players = MusicPlayers.SystemMedia(allowsApplicationBundleIdentifiers: defaults[.systemWideNowPlayingAppList]).map { [$0] } ?? []
                } else {
                    players = MusicPlayerName.scriptableCases.compactMap(MusicPlayers.Scriptable.init)
                }
                designatedPlayer = AutomaticPlayer(players: players + [PhonePlayer.shared])
            } else {
                designatedPlayer = MusicPlayerName(index: idx).flatMap(MusicPlayers.Scriptable.init)
            }
        }

        var activePlayer: MusicPlayerProtocol? {
            var player = designatedPlayer
            var visited = Set<ObjectIdentifier>()
            while let agent = player as? MusicPlayers.Agent {
                guard visited.insert(ObjectIdentifier(agent)).inserted else { return nil }
                player = agent.designatedPlayer
            }
            return player
        }

        private var scheduleCanceller: Cancellable?
        func scheduleManualUpdate() {
            scheduleCanceller?.cancel()
            guard manualUpdateInterval > 0 else { return }
            let q = DispatchQueue.main
            let i: DispatchQueue.SchedulerTimeType.Stride = .seconds(manualUpdateInterval)
            scheduleCanceller = q.schedule(after: q.now.advanced(by: i), interval: i, tolerance: i * 0.1, options: nil) { [unowned self] in
                if let automatic = self.designatedPlayer as? AutomaticPlayer {
                    automatic.refreshCandidates()
                } else {
                    self.designatedPlayer?.updatePlayerState()
                }
            }
        }
    }
}

extension MusicPlayers.SystemMedia: Then {}
