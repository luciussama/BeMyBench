import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Janela inicial confortável para o dashboard desktop.
    let defaultSize = NSSize(width: 1280, height: 840)
    self.setContentSize(defaultSize)
    self.minSize = NSSize(width: 560, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
