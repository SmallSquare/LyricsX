import AppKit
import LyricsXFoundation

class PreferenceLabViewController: PreferenceViewController {
    @IBOutlet var enableTouchBarLyricsButton: NSButton!

    @IBOutlet var musixmatchTokenField: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        enableTouchBarLyricsButton.bind(.value, withDefaultName: .touchBarLyricsEnabled)
        setupPlaybackControlsPreference()

        if let token = defaults[.musixmatchToken] {
            musixmatchTokenField.stringValue = token
        } else {
            musixmatchTokenField.stringValue = ""
        }

    }

    private func setupPlaybackControlsPreference() {
        guard let grid = view.subviews.compactMap({ $0 as? NSGridView }).first else { return }
        let toggle = NSButton(checkboxWithTitle: NSLocalizedString("Show music controls in the lyrics menu", comment: "Playback preferences"), target: nil, action: nil)
        toggle.bind(.value, withDefaultName: .playbackControlsEnabled)
        let row = grid.insertRow(at: 1, with: [NSGridCell.emptyContentView, toggle])
        row.height = 24
        row.yPlacement = .center
        let height = view.frame.height + 30
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
        preferredContentSize = NSSize(width: view.frame.width, height: height)
    }

    @IBAction func musixmatchTokenChanged(_ sender: NSTextField) {
        let value = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            defaults.remove(.musixmatchToken)
        } else {
            defaults[.musixmatchToken] = value
        }
        
        // Update lyrics manager when token changes
        Task { @MainActor in
            try await AppController.shared.updateLyricsManager()
        }
    }

    @IBAction func customizeAllowsNowPlayingApplicationsAction(_ sender: NSButton) {
        let viewController = NowPlayingApplicationListViewController()
        viewController.preferredContentSize = .init(width: 600, height: 500)
        presentAsSheet(viewController)
    }

    @IBAction func customizeTouchBarAction(_ sender: NSButton) {
        NSApplication.shared.toggleTouchBarCustomizationPalette(sender)
    }
}
