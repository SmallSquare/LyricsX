import Combine
import Foundation
import MusicPlayer

/// Observe every candidate, including when the currently selected source pauses.
/// Keep a playing source stable; otherwise prefer playing, then paused content.
final class AutomaticPlayer: MusicPlayers.Agent {
    private let players: [MusicPlayerProtocol]
    private var observations = Set<AnyCancellable>()

    init(players: [MusicPlayerProtocol]) {
        self.players = players
        super.init()
        for player in players {
            player.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.selectPlayer() }
                .store(in: &observations)
        }
        selectPlayer()
    }

    private func selectPlayer() {
        let next: MusicPlayerProtocol?
        if designatedPlayer?.playbackState.isPlaying == true {
            next = designatedPlayer
        } else if let playing = players.first(where: { $0.playbackState.isPlaying }) {
            next = playing
        } else if let current = designatedPlayer,
                  current.playbackState != .stopped, current.currentTrack != nil {
            next = current
        } else {
            next = players.first { $0.playbackState != .stopped && $0.currentTrack != nil }
        }
        if next !== designatedPlayer { designatedPlayer = next }
    }

    func refreshCandidates() {
        // Candidates deliver their own notifications while idle. An explicit
        // refresh also catches sources that were not previously selected.
        players.forEach { $0.updatePlayerState() }
        selectPlayer()
    }
}
