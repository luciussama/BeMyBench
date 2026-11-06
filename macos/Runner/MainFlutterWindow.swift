import Cocoa
import FlutterMacOS
import Metal
import MetalKit
import QuartzCore

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
            let payload = try GpuBenchmark.shared.runCompute(durationMs: durationMs)
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

      case "run_render":
        let args = call.arguments as? [String: Any]
        let durationMs = args?["duration_ms"] as? Int ?? 1500
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let payload = try GpuBenchmark.shared.runRender(durationMs: durationMs)
            DispatchQueue.main.async { result(payload) }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "gpu_render_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }

      case "open_3d_window":
        let args = call.arguments as? [String: Any]
        let mode = args?["mode"] as? String ?? "stress"
        DispatchQueue.main.async {
          GpuLiveWindowController.shared.show(mode: mode)
          result(true)
        }

      case "close_3d_window":
        DispatchQueue.main.async {
          GpuLiveWindowController.shared.closeWindow()
          result(true)
        }

      case "is_3d_window_open":
        DispatchQueue.main.async {
          result(GpuLiveWindowController.shared.isOpen)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.gpuChannel = channel

    super.awakeFromNib()
  }
}

// =====================================================================
// Janela 3D Nativa (Metal / FurMark-like) com VSync OFF e HUD
// =====================================================================

final class GpuLiveWindowController: NSObject, NSWindowDelegate, MTKViewDelegate {
  static let shared = GpuLiveWindowController()

  private var window: NSWindow?
  private var mtkView: MTKView?
  private var hudView: NSVisualEffectView?

  // HUD Labels
  private let gpuLabel = NSTextField(labelWithString: "GPU: —")
  private let fpsLabel = NSTextField(labelWithString: "FPS: 0.0")
  private let frameTimeLabel = NSTextField(labelWithString: "Frame: 0.0 ms")
  private let vramLabel = NSTextField(labelWithString: "V-RAM: —")
  private let vsyncLabel = NSTextField(labelWithString: "VSync: OFF (Livre)")
  private let statusLabel = NSTextField(labelWithString: "Status: Rodando")
  private let modeControl = NSSegmentedControl(labels: ["Benchmark (15s)", "Estresse"], trackingMode: .selectOne, target: nil, action: nil)

  // Métricas de render
  private var frameCount: Int = 0
  private var startTimeNs: UInt64 = 0
  private var lastFrameTimeNs: UInt64 = 0
  private var recentFrameDeltas: [Double] = []
  private var currentMode: String = "stress" // "benchmark" ou "stress"
  private var isBenchmarkComplete: Bool = false
  private var peakFps: Double = 0.0
  private var minFps: Double = 0.0
  private var benchmarkScore: Double = 0.0

  var isOpen: Bool {
    window?.isVisible ?? false
  }

  func show(mode: String = "stress") {
    currentMode = mode
    isBenchmarkComplete = false
    frameCount = 0
    startTimeNs = DispatchTime.now().uptimeNanoseconds
    lastFrameTimeNs = startTimeNs
    recentFrameDeltas.removeAll(keepingCapacity: true)
    peakFps = 0.0
    minFps = 0.0
    benchmarkScore = 0.0

    if let w = window {
      updateModeSelection()
      mtkView?.isPaused = false
      w.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    createWindow()
    updateModeSelection()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func closeWindow() {
    mtkView?.isPaused = true
    window?.orderOut(nil)
  }

  private func createWindow() {
    let rect = NSRect(x: 120, y: 120, width: 960, height: 540)
    let w = NSWindow(
      contentRect: rect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    w.title = "BMyBench — Render 3D GPU (FurMark-like)"
    w.minSize = NSSize(width: 540, height: 320)
    w.isReleasedWhenClosed = false
    w.level = .floating
    w.delegate = self
    w.center()

    guard let dev = GpuBenchmark.shared.metalDevice else { return }

    let view = MTKView(frame: rect, device: dev)
    view.colorPixelFormat = .bgra8Unorm
    view.depthStencilPixelFormat = .depth32Float
    view.clearColor = MTLClearColorMake(0.04, 0.06, 0.09, 1.0)
    view.isPaused = false
    view.enableSetNeedsDisplay = false
    view.autoResizeDrawable = false
    view.drawableSize = CGSize(width: 1920, height: 1080)
    view.preferredFramesPerSecond = 120
    view.delegate = self

    // VSync OFF: desliga sincronização de display na CAMetalLayer
    if let layer = view.layer as? CAMetalLayer {
      layer.displaySyncEnabled = false
      layer.allowsNextDrawableTimeout = false
    }

    setupHud(over: view, dev: dev)

    w.contentView = view
    self.window = w
    self.mtkView = view
  }

  private func setupHud(over parentView: NSView, dev: MTLDevice) {
    let hud = NSVisualEffectView(frame: NSRect(x: 16, y: 16, width: 280, height: 210))
    hud.material = .hudWindow
    hud.state = .active
    hud.wantsLayer = true
    hud.layer?.cornerRadius = 8
    hud.layer?.masksToBounds = true
    hud.layer?.borderColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.5).cgColor
    hud.layer?.borderWidth = 1.0

    // Auto-resizing para ficar sempre no canto superior esquerdo
    hud.autoresizingMask = [.minXMargin, .minYMargin]

    let stack = NSStackView(frame: NSRect(x: 12, y: 10, width: 256, height: 190))
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4

    let titleLabel = NSTextField(labelWithString: "BMyBench GPU Live")
    titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
    titleLabel.textColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0)

    gpuLabel.stringValue = "GPU: \(dev.name)"
    gpuLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    gpuLabel.textColor = .white

    fpsLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)
    fpsLabel.textColor = NSColor(red: 0.98, green: 0.45, blue: 0.08, alpha: 1.0) // Orange accent

    frameTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    frameTimeLabel.textColor = .lightGray

    let workingSetMb = Int(dev.recommendedMaxWorkingSetSize / (1024 * 1024))
    vramLabel.stringValue = "V-RAM: \(workingSetMb) MB (alocada)"
    vramLabel.font = NSFont.systemFont(ofSize: 10)
    vramLabel.textColor = .lightGray

    vsyncLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
    vsyncLabel.textColor = NSColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1.0) // Green

    statusLabel.font = NSFont.systemFont(ofSize: 10)
    statusLabel.textColor = .white

    modeControl.target = self
    modeControl.action = #selector(modeChanged(_:))
    modeControl.controlSize = .small

    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(gpuLabel)
    stack.addArrangedSubview(fpsLabel)
    stack.addArrangedSubview(frameTimeLabel)
    stack.addArrangedSubview(vramLabel)
    stack.addArrangedSubview(vsyncLabel)
    stack.addArrangedSubview(statusLabel)
    stack.addArrangedSubview(modeControl)

    hud.addSubview(stack)
    parentView.addSubview(hud)
    self.hudView = hud
  }

  private func updateModeSelection() {
    modeControl.selectedSegment = currentMode == "benchmark" ? 0 : 1
    statusLabel.stringValue = currentMode == "benchmark" ? "Status: Benchmark (15s)" : "Status: Estresse contínuo"
  }

  @objc private func modeChanged(_ sender: NSSegmentedControl) {
    let newMode = sender.selectedSegment == 0 ? "benchmark" : "stress"
    show(mode: newMode)
  }

  // MARK: - MTKViewDelegate

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    if isBenchmarkComplete {
      return
    }

    guard let drawable = view.currentDrawable,
          let queue = GpuBenchmark.shared.commandQueue,
          let cb = queue.makeCommandBuffer() else {
      return
    }

    let nowNs = DispatchTime.now().uptimeNanoseconds
    let frameDelta = Double(nowNs - lastFrameTimeNs) / 1_000_000_000.0
    lastFrameTimeNs = nowNs
    if frameDelta > 0 && frameDelta < 0.5 {
      recentFrameDeltas.append(frameDelta)
      if recentFrameDeltas.count > 45 {
        recentFrameDeltas.removeFirst()
      }
    }

    frameCount += 1

    // Executa os passes 3D Metal em tempo real na textura do drawable
    let ok = GpuBenchmark.shared.encodeRenderFrame(cb, frameIndex: frameCount, targetTexture: drawable.texture)
    if ok {
      cb.present(drawable)
      cb.commit()
    }

    // Atualiza HUD na main thread periodicamente (a cada ~8 frames)
    if frameCount % 8 == 0 {
      let elapsedSec = Double(nowNs - startTimeNs) / 1_000_000_000.0
      let avgDelta = recentFrameDeltas.isEmpty ? 0.016 : recentFrameDeltas.reduce(0, +) / Double(recentFrameDeltas.count)
      let curFps = avgDelta > 0 ? 1.0 / avgDelta : 0.0
      let frameMs = avgDelta * 1000.0

      if peakFps == 0.0 || curFps > peakFps { peakFps = curFps }
      if minFps == 0.0 || (curFps < minFps && frameCount > 30) { minFps = curFps }

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.fpsLabel.stringValue = String(format: "FPS: %.1f", curFps)
        self.frameTimeLabel.stringValue = String(format: "Frame: %.2f ms", frameMs)

        if self.currentMode == "benchmark" {
          let remaining = max(0.0, 15.0 - elapsedSec)
          self.statusLabel.stringValue = String(format: "Tempo: %.1fs / 15.0s", elapsedSec)
          if remaining <= 0.0 && !self.isBenchmarkComplete {
            self.isBenchmarkComplete = true
            let totalAvgFps = Double(self.frameCount) / elapsedSec
            self.benchmarkScore = totalAvgFps * 100.0
            self.statusLabel.stringValue = String(format: "Concluído! Score: %.0f", self.benchmarkScore)
            self.statusLabel.textColor = NSColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1.0)
          }
        } else {
          let drop = self.peakFps > 0 ? max(0, (self.peakFps - curFps) / self.peakFps * 100.0) : 0.0
          self.statusLabel.stringValue = String(format: "Tempo: %02d:%02d | Queda: %.0f%%", Int(elapsedSec) / 60, Int(elapsedSec) % 60, drop)
        }
      }
    }
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    mtkView?.isPaused = true
    sender.orderOut(nil)
    return false
  }
}
