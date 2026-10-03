import Cocoa

class PreferenceTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let item = NSTabViewItem(viewController: PreferencePhoneViewController())
        item.identifier = "PhonePlayer"
        item.label = NSLocalizedString("Phone", comment: "Phone source")
        if #available(macOS 11, *) { item.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil) }
        else { item.image = NSImage(named: NSImage.Name("NSBluetoothTemplate")) }
        addTabViewItem(item)
    }
}

class PreferenceViewController: NSViewController {
//    override func viewWillAppear() {
//        super.viewWillAppear()
//        view.subviews.first?.alphaValue = 0
//        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
//            self.view.subviews.first?.animator().alphaValue = 1
//        }
//    }
//
//    override func viewWillDisappear() {
//        super.viewWillDisappear()
//        view.subviews.first?.animator().alphaValue = 0
//    }
}
