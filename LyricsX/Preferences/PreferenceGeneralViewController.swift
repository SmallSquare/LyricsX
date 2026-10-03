import AppKit
import MusicPlayer
import ServiceManagement
import LaunchAtLogin

class PreferenceGeneralViewController: PreferenceViewController {
    @objc dynamic var launchAtLogin = LaunchAtLogin.kvo
    private let preferPhone = NSButton(radioButtonWithTitle: NSLocalizedString("Phone (Bluetooth)", comment: "Phone source"), target: nil, action: nil)
    @IBOutlet var preferAuto: NSButton!
    @IBOutlet var preferiTunes: NSButton!
    @IBOutlet var preferSpotify: NSButton!
    @IBOutlet var preferVox: NSButton!
    @IBOutlet var preferAudirvana: NSButton!
    @IBOutlet var preferSwinsian: NSButton!

    @IBOutlet var autoLaunchButton: NSButton!

    @IBOutlet var savingPathPopUp: NSPopUpButton!
    @IBOutlet var userPathMenuItem: NSMenuItem!

    @IBOutlet var loadHomonymLrcButton: NSButton!

    @IBOutlet var languagePopUp: NSPopUpButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        if let grid = view.subviews.compactMap({ $0 as? NSGridView }).first {
            preferPhone.tag = PhonePlayer.preferenceIndex
            preferPhone.target = self; preferPhone.action = #selector(preferredPlayerAction(_:))
            let configure = NSButton(title: NSLocalizedString("Connection Settings…", comment: "Phone source"), target: self, action: #selector(showPhoneSettings))
            let row = NSStackView(views: [preferPhone, configure])
            row.orientation = .horizontal; row.spacing = 16
            grid.insertRow(at: 0, with: [NSGridCell.emptyContentView, row]).height = 30
            view.setFrameSize(NSSize(width: view.frame.width, height: view.frame.height + 40))
        }

        if let url = defaults.lyricsCustomSavingPath {
            userPathMenuItem.title = url.lastPathComponent
            userPathMenuItem.toolTip = url.path
        } else {
            userPathMenuItem.isHidden = true
        }

        let localizedLan: [String] = localizations.map { lan in
            if let idx = lan.firstIndex(of: "-") {
                let script = lan[idx...].dropFirst()
                return Locale(identifier: lan).localizedString(forScriptCode: String(script))!
            } else {
                return Locale(identifier: lan).localizedString(forLanguageCode: lan)!
            }
        }
        languagePopUp.addItems(withTitles: localizedLan)

        if let lan = defaults[.selectedLanguage],
           let idx = localizations.firstIndex(of: lan) {
            languagePopUp.selectItem(at: idx + 2)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let index = defaults[.preferredPlayerIndex]
        for (button, tag) in [(preferAuto!, -1), (preferiTunes!, 0), (preferSpotify!, 1), (preferVox!, 2), (preferAudirvana!, 3), (preferSwinsian!, 4), (preferPhone, PhonePlayer.preferenceIndex)] {
            button.state = index == tag ? .on : .off
        }
        autoLaunchButton.isEnabled = index >= 0 && index != PhonePlayer.preferenceIndex
        loadHomonymLrcButton.isEnabled = ![1, 3, 4, PhonePlayer.preferenceIndex].contains(index)
    }

    @IBAction func toggleAutoLaunchAction(_ sender: NSButton) {
        let enabled = sender.state == .on
        if #available(macOS 13, *) {
            let service = SMAppService.loginItem(identifier: lyricsXHelperIdentifier)
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                log("SMAppService \(enabled ? "register" : "unregister") failed: \(error)")
            }
        } else {
            if !SMLoginItemSetEnabled(lyricsXHelperIdentifier as CFString, enabled) {
                log("Failed to set login item enabled")
            }
        }
    }

    @IBAction func showInFinderAction(_ sender: Any) {
        let url = defaults.lyricsSavingPath().0
        NSWorkspace.shared.open(url)
    }

    @IBAction func chooseSavingPathAction(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.beginSheetModal(for: view.window!) { result in
            if result == .OK {
                let url = openPanel.url!
                defaults.lyricsCustomSavingPath = url
                self.userPathMenuItem.title = url.lastPathComponent
                self.userPathMenuItem.toolTip = url.path
                self.userPathMenuItem.isHidden = false
                self.savingPathPopUp.select(self.userPathMenuItem)
            } else {
                self.savingPathPopUp.selectItem(at: 0)
            }
        }
    }

    @IBAction func chooseLanguageAction(_ sender: NSPopUpButton) {
        let selectedIdx = sender.indexOfSelectedItem
        if selectedIdx == 0 {
            defaults.remove(.selectedLanguage)
            defaults.remove(.appleLanguages)
        } else {
            let lan = localizations[selectedIdx - 2]
            defaults[.selectedLanguage] = lan
            defaults[.appleLanguages] = [lan]
        }
    }

    @IBAction func helpTranslateAction(_ sender: NSButton) {
        NSWorkspace.shared.open(crowdinProjectURL)
    }

    @IBAction func preferredPlayerAction(_ sender: NSButton) {
        for (button, tag) in [(preferAuto!, -1), (preferiTunes!, 0), (preferSpotify!, 1), (preferVox!, 2), (preferAudirvana!, 3), (preferSwinsian!, 4), (preferPhone, PhonePlayer.preferenceIndex)] {
            button.state = sender.tag == tag ? .on : .off
        }
        defaults[.preferredPlayerIndex] = sender.tag

        if sender.tag < 0 || sender.tag == PhonePlayer.preferenceIndex {
            autoLaunchButton.isEnabled = false
            autoLaunchButton.state = .off
            defaults[.launchAndQuitWithPlayer] = false
        } else {
            autoLaunchButton.isEnabled = true
        }

        if sender.tag == 1 || sender.tag == 3 || sender.tag == 4 || sender.tag == PhonePlayer.preferenceIndex {
            loadHomonymLrcButton.isEnabled = false
            loadHomonymLrcButton.state = .off
            defaults[.loadLyricsBesideTrack] = false
        } else {
            loadHomonymLrcButton.isEnabled = true
        }
    }
    @objc private func showPhoneSettings() {
        guard let tabs = parent as? NSTabViewController,
              let index = tabs.tabViewItems.firstIndex(where: { $0.identifier as? String == "PhonePlayer" }) else { return }
        tabs.selectedTabViewItemIndex = index
    }
}

private let localizations = Bundle.main.localizations.filter { !$0.localizedCaseInsensitiveContains("Base") }.sorted()
