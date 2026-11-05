import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var gpuChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Janela inicial confortável para o dashboard desktop.
    let defaultSize = NSSize(width: 1280, height: 840)
    self.setContentSize(defaultSize)
    self.minSize = NSSize(width: 560, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "bemybench/gpu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "info":
        result(GpuBenchmark.shared.info())

      case "run":
        let args = call.arguments as? [String: Any]
        let durationMs = args?["duration_ms"] as? Int ?? 1500
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let payload = try GpuBenchmark.shared.run(durationMs: durationMs)
            DispatchQueue.main.async { result(payload) }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "gpu_bench_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.gpuChannel = channel

    super.awakeFromNib()
  }
}
