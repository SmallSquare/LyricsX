import AppKit
import MediaRemoteAdapter
import MusicPlayer

/// Bring the selected source application's normal window forward.
enum PlaybackPlayerLauncher {
    static func open(_ player: MusicPlayerProtocol) {
        var source = player
        while let agent = source as? MusicPlayers.Agent, let next = agent.designatedPlayer, next !== source {
            source = next
        }
        if let scriptable = source as? MusicPlayers.Scriptable {
            open(bundleIdentifier: scriptable.playerBundleID)
        } else if let system = source as? MusicPlayers.SystemMedia, let expected = player.currentTrack {
            let controller = MediaController(bundleIdentifiers: system.allowsApplicationBundleIdentifiers)
            controller.onTrackInfoReceived = { [weak player] info, _ in
                guard let info = info, player?.currentTrack?.id == expected.id else { return }
                var title = info.title
                var artist = info.artist
                // SystemMedia also recovers metadata packed into a single field by some sources.
                for field in [info.title, info.artist] {
                    if let field = field, let range = field.range(of: " — ") {
                        title = String(field[..<range.lowerBound])
                        artist = String(field[range.upperBound...])
                        break
                    }
                }
                guard PlaybackArtworkLoader.matches(expected, title: title, artist: artist, album: info.album),
                      let bundleID = info.parentApplicationBundleIdentifier ?? info.bundleIdentifier else { return }
                DispatchQueue.main.async { open(bundleIdentifier: bundleID) }
            }
            controller.updatePlayerState()
        }
    }

    private static func open(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }
}
