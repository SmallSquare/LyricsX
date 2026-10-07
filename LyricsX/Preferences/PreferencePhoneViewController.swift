import AppKit
import Combine

final class PreferencePhoneViewController: PreferenceViewController {
    private let devices = NSPopUpButton(frame: .zero, pullsDown: false)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let artwork = NSImageView()
    private let connectButton = NSButton(title: NSLocalizedString("Connect", comment: "Phone source"), target: nil, action: nil)
    private let disconnectButton = NSButton(title: NSLocalizedString("Disconnect", comment: "Phone source"), target: nil, action: nil)
    private let reconnect = NSButton(checkboxWithTitle: NSLocalizedString("Reconnect automatically", comment: "Phone source"), target: nil, action: nil)
    private var observation: AnyCancellable?
    private let inventory = PhoneDeviceInventory()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 611, height: 320))
        let heading = NSTextField(labelWithString: "AVRCP")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: NSLocalizedString("Choose your paired phone. Keep your headphones connected to the phone. LyricsX requests song information and playback controls only.", comment: "Phone source"))
        help.textColor = .secondaryLabelColor
        let refresh = NSButton(title: NSLocalizedString("Refresh Devices", comment: "Phone source"), target: self, action: #selector(refreshDevices))
        let settings = NSButton(title: NSLocalizedString("Bluetooth Settings…", comment: "Phone source"), target: self, action: #selector(openBluetoothSettings))
        connectButton.target = self; connectButton.action = #selector(connectPhone)
        disconnectButton.target = self; disconnectButton.action = #selector(disconnectPhone)
        reconnect.target = self; reconnect.action = #selector(changeReconnect)
        reconnect.state = PhonePlayer.shared.autoReconnect ? .on : .off
        let deviceRow = NSStackView(views: [devices, refresh])
        deviceRow.orientation = .horizontal; deviceRow.spacing = 8
        let commands = NSStackView(views: [connectButton, disconnectButton, settings])
        commands.orientation = .horizontal; commands.spacing = 8
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let compatibility = NSTextField(wrappingLabelWithString: NSLocalizedString("Bluetooth compatibility depends on the phone. Song information and playback position are required. Cover art is shown when the phone supports it; seeking is not available.", comment: "Phone source"))
        compatibility.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        compatibility.textColor = .secondaryLabelColor
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.setAccessibilityLabel(NSLocalizedString("Album Artwork", comment: "Playback artwork"))
        artwork.widthAnchor.constraint(equalToConstant: 40).isActive = true
        artwork.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let playbackRow = NSStackView(views: [artwork, status])
        playbackRow.orientation = .horizontal; playbackRow.spacing = 10
        let stack = NSStackView(views: [heading, help, deviceRow, commands, reconnect, playbackRow, compatibility])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            devices.widthAnchor.constraint(equalToConstant: 330),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            playbackRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            compatibility.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        observation = PhonePlayer.shared.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.updateStatus() }
    }
    override func viewWillAppear() { super.viewWillAppear(); refreshDevices(); updateStatus() }
    @objc private func refreshDevices() {
        let selected = devices.selectedItem?.representedObject as? String ?? PhonePlayer.shared.savedAddress
        devices.isEnabled = false
        inventory.refresh { [weak self] paired in
            guard let self = self else { return }
            self.devices.removeAllItems()
            for device in paired {
                self.devices.addItem(withTitle: device.name)
                self.devices.lastItem?.representedObject = device.address
                if device.address == selected { self.devices.select(self.devices.lastItem) }
            }
            if self.devices.numberOfItems == 0 {
                self.devices.addItem(withTitle: NSLocalizedString("No paired devices", comment: "Phone source"))
            } else { self.devices.isEnabled = true }
            self.updateStatus()
        }
        updateStatus()
    }

    private func updateStatus() {
        let phone = PhonePlayer.shared
        artwork.image = phone.currentTrack?.artwork
        artwork.isHidden = artwork.image == nil
        status.stringValue = phone.statusMessage
        if phone.isConnected, let track = phone.currentTrack {
            let metadata = [track.title, track.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            func time(_ value: TimeInterval) -> String {
                guard value.isFinite, value >= 0 else { return "–:––" }
                let seconds = Int(min(value, Double(Int32.max)))
                return String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
            let progress = time(phone.playbackTime) + " / " + (track.duration.map(time) ?? "–:––")
            status.stringValue += "\n" + metadata + "  " + progress
        }
        if phone.isConnected {
            let key: String
            if phone.isUsingArtworkFallback {
                key = "Bluetooth cover unavailable; online artwork loaded."
            } else {
                switch phone.artworkState {
                case .unavailable: key = "Phone cover art is currently unavailable."
                case .connecting, .loading: key = "Loading phone cover art…"
                case .ready: key = "Waiting for phone cover art…"
                case .loaded: key = "Phone cover art loaded."
                }
            }
            status.stringValue += "\n" + NSLocalizedString(key, comment: "Phone artwork status")
        }
        connectButton.isEnabled = devices.selectedItem?.representedObject is String && !phone.isConnecting
        disconnectButton.isEnabled = phone.isConnected || phone.isConnecting
    }
    @objc private func connectPhone() {
        guard let address = devices.selectedItem?.representedObject as? String else { return }
        defaults[.launchAndQuitWithPlayer] = false
        defaults[.loadLyricsBesideTrack] = false
        let name = devices.titleOfSelectedItem ?? NSLocalizedString("Phone", comment: "Phone source")
        if defaults[.preferredPlayerIndex] == -1 || defaults[.preferredPlayerIndex] == PhonePlayer.preferenceIndex {
            PhonePlayer.shared.connect(address: address, name: name)
        } else {
            PhonePlayer.shared.remember(address: address, name: name)
            defaults[.preferredPlayerIndex] = PhonePlayer.preferenceIndex
        }
        updateStatus()
    }
    @objc private func disconnectPhone() { PhonePlayer.shared.disconnect(); updateStatus() }
    @objc private func changeReconnect() { PhonePlayer.shared.autoReconnect = reconnect.state == .on }
    @objc private func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
}
