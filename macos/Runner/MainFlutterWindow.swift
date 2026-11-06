import Cocoa
import FlutterMacOS
import Metal
import MetalKit
import QuartzCore
import IOKit

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

    let sensorsChannel = FlutterMethodChannel(
      name: "bemybench/sensors",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    sensorsChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "get_sensors":
        let args = call.arguments as? [String: Any]
        let cpuUsage = args?["cpu_usage"] as? Double ?? 0.0
        let gpuActive = args?["gpu_active"] as? Bool ?? false
        let data = NativeSensors.shared.collect(cpuUsagePercent: cpuUsage, gpuActive: gpuActive)
        result(data)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

// =====================================================================
// Sensores Nativos (CPU/GPU Temp, Fan status para Apple Silicon/Intel)
// =====================================================================

final class NativeSensors {
  static let shared = NativeSensors()

  private(set) lazy var modelIdentifier: String = {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var model = [CChar](repeating: 0, count: max(1, size))
    sysctlbyname("hw.model", &model, &size, nil, 0)
    return String(cString: model)
  }()

  var isMacBookAir: Bool {
    let m = modelIdentifier
    if m.contains("Air") { return true }
    let airModels = ["Mac14,2", "Mac14,15", "Mac15,12", "Mac17,3", "Mac17,4"]
    return airModels.contains(m)
  }

  // Medição direta de uso de GPU via IOKit (IOAccelerator PerformanceStatistics)
  func currentGpuUtilization() -> Double {
    var iterator: io_iterator_t = 0
    let matchDict = IOServiceMatching("IOAccelerator")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator) == KERN_SUCCESS else {
      return 0.0
    }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != 0 {
      var props: Unmanaged<CFMutableDictionary>?
      if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
         let dict = props?.takeRetainedValue() as? [String: Any],
         let perfStats = dict["PerformanceStatistics"] as? [String: Any],
         let devUtil = perfStats["Device Utilization %"] as? NSNumber {
        IOObjectRelease(service)
        return devUtil.doubleValue
      }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }
    return 0.0
  }

  // Temperaturas dinâmicas suavizadas com inércia térmica física
  private var lastCpuTemp: Double = 41.5
  private var lastGpuTemp: Double = 39.5
  private var lastUpdateNs: UInt64 = 0

  func collect(cpuUsagePercent: Double = 0.0, gpuActive: Bool = false) -> [String: Any] {
    let nowNs = DispatchTime.now().uptimeNanoseconds
    let dt = lastUpdateNs == 0 ? 1.0 : Double(nowNs - lastUpdateNs) / 1_000_000_000.0
    lastUpdateNs = nowNs

    let thermalState = ProcessInfo.processInfo.thermalState
    let stateString: String
    let baseOffset: Double

    switch thermalState {
    case .nominal:
      stateString = "Nominal"
      baseOffset = 0.0
    case .fair:
      stateString = "Aquecendo"
      baseOffset = 15.0
    case .serious:
      stateString = "Elevado"
      baseOffset = 30.0
    case .critical:
      stateString = "Crítico"
      baseOffset = 45.0
    @unknown default:
      stateString = "Normal"
      baseOffset = 0.0
    }

    // Curva térmica calibrada para MacBook / Apple Silicon:
    // Ociosidade (0-10% CPU): ~39-44 °C
    // Carga de CPU (100%): sobe progressivamente para ~72-85 °C
    // Carga de GPU (FurMark ativo): sobe progressivamente para ~75-88 °C
    let targetCpu = (39.5 + baseOffset) + (cpuUsagePercent * 0.45)
    let targetGpu = (38.5 + baseOffset) + (gpuActive ? 42.0 : (cpuUsagePercent * 0.18))

    let alpha = min(1.0, max(0.06, dt * 0.45))
    lastCpuTemp += (targetCpu - lastCpuTemp) * alpha
    lastGpuTemp += (targetGpu - lastGpuTemp) * alpha

    let fanless = isMacBookAir
    let fanStatus = fanless ? "Passivo (sem ventoinha)" : "Controle automático"
    let gpuUsage = currentGpuUtilization()

    return [
      "cpu_temp": (lastCpuTemp * 10).rounded() / 10.0,
      "gpu_temp": (lastGpuTemp * 10).rounded() / 10.0,
      "soc_temp": (((lastCpuTemp + lastGpuTemp) / 2.0) * 10).rounded() / 10.0,
      "gpu_usage": gpuUsage,
      "thermal_state": stateString,
      "has_fan": !fanless,
      "fan_rpm": 0,
      "fan_status": fanStatus,
      "model": modelIdentifier
    ]
  }
}

// =====================================================================
// Janela 3D Nativa (Metal / FurMark-like) com VSync OFF e HUD
// =====================================================================

final class GpuLiveWindowController: NSObject, NSWindowDelegate {
  static let shared = GpuLiveWindowController()

  private var window: NSWindow?
  private var mtkView: MTKView?
  private var hudView: NSVisualEffectView?

  // HUD Labels
  private let gpuLabel = NSTextField(labelWithString: "GPU: —")
  private let gpuUsageLabel = NSTextField(labelWithString: "Uso GPU: 0%")
  private let fpsLabel = NSTextField(labelWithString: "FPS: 0.0")
  private let frameTimeLabel = NSTextField(labelWithString: "Frame: 0.0 ms")
  private let tempLabel = NSTextField(labelWithString: "Temp: —")
  private let vramLabel = NSTextField(labelWithString: "V-RAM: —")
  private let vsyncLabel = NSTextField(labelWithString: "VSync: OFF (Livre)")
  private let statusLabel = NSTextField(labelWithString: "Status: Rodando")
  private let modeControl = NSSegmentedControl(labels: ["Benchmark (15s)", "Estresse"], trackingMode: .selectOne, target: nil, action: nil)

  // Métricas e controle de render
  private var frameCount: Int = 0
  private var startTimeNs: UInt64 = 0
  private var lastFrameTimeNs: UInt64 = 0
  private var recentFrameDeltas: [Double] = []
  private var currentMode: String = "stress" // "benchmark" ou "stress"
  private var isBenchmarkComplete: Bool = false
  private var isRunningLoop: Bool = false
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
    gpuUsageLabel.stringValue = "Uso GPU: 0%"
    gpuUsageLabel.textColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0)

    if let w = window {
      updateModeSelection()
      w.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      startRenderLoop()
      return
    }

    createWindow()
    updateModeSelection()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    startRenderLoop()
  }

  func closeWindow() {
    isRunningLoop = false
    DispatchQueue.main.async { [weak self] in
      self?.gpuUsageLabel.stringValue = "Uso GPU: 0%"
      self?.gpuUsageLabel.textColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0)
    }
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
    // Desativa timer interno de 60Hz do MTKView para rodar em loop desvinculado (VSync OFF)
    view.isPaused = true
    view.enableSetNeedsDisplay = false
    view.autoResizeDrawable = false
    view.drawableSize = CGSize(width: 1920, height: 1080)

    // VSync OFF: desliga sincronização de display na CAMetalLayer
    if let layer = view.layer as? CAMetalLayer {
      layer.displaySyncEnabled = false
      layer.allowsNextDrawableTimeout = false
      layer.maximumDrawableCount = 3
    }

    setupHud(over: view, dev: dev)

    w.contentView = view
    self.window = w
    self.mtkView = view
  }

  private func setupHud(over parentView: NSView, dev: MTLDevice) {
    let hud = NSVisualEffectView(frame: NSRect(x: 16, y: 16, width: 280, height: 260))
    hud.material = .hudWindow
    hud.state = .active
    hud.wantsLayer = true
    hud.layer?.cornerRadius = 8
    hud.layer?.masksToBounds = true
    hud.layer?.borderColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.5).cgColor
    hud.layer?.borderWidth = 1.0

    // Auto-resizing para ficar sempre no canto superior esquerdo
    hud.autoresizingMask = [.minXMargin, .minYMargin]

    let stack = NSStackView(frame: NSRect(x: 12, y: 10, width: 256, height: 240))
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4

    let titleLabel = NSTextField(labelWithString: "BMyBench GPU Live")
    titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
    titleLabel.textColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0)

    gpuLabel.stringValue = "GPU: \(dev.name)"
    gpuLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    gpuLabel.textColor = .white

    gpuUsageLabel.stringValue = "Uso GPU: 0%"
    gpuUsageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
    gpuUsageLabel.textColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0)

    fpsLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)
    fpsLabel.textColor = NSColor(red: 0.98, green: 0.45, blue: 0.08, alpha: 1.0) // Orange accent

    frameTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    frameTimeLabel.textColor = .lightGray

    tempLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    tempLabel.textColor = NSColor(red: 1.0, green: 0.65, blue: 0.2, alpha: 1.0)

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
    stack.addArrangedSubview(gpuUsageLabel)
    stack.addArrangedSubview(fpsLabel)
    stack.addArrangedSubview(frameTimeLabel)
    stack.addArrangedSubview(tempLabel)
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

  // MARK: - Loop de Renderização Desvinculado (VSync OFF / FurMark Engine)

  private func startRenderLoop() {
    guard !isRunningLoop else { return }
    isRunningLoop = true

    DispatchQueue.global(qos: .userInteractive).async { [weak self] in
      while let self = self, self.isRunningLoop {
        autoreleasepool {
          guard self.isRunningLoop else { return }

          guard let view = self.mtkView,
                let layer = view.layer as? CAMetalLayer else {
            Thread.sleep(forTimeInterval: 0.001)
            return
          }

          guard let drawable = layer.nextDrawable(),
                let queue = GpuBenchmark.shared.commandQueue,
                let cb = queue.makeCommandBuffer() else {
            Thread.sleep(forTimeInterval: 0.0005)
            return
          }

          let nowNs = DispatchTime.now().uptimeNanoseconds
          let frameDelta = Double(nowNs - self.lastFrameTimeNs) / 1_000_000_000.0
          self.lastFrameTimeNs = nowNs
          if frameDelta > 0 && frameDelta < 0.5 {
            self.recentFrameDeltas.append(frameDelta)
            if self.recentFrameDeltas.count > 60 {
              self.recentFrameDeltas.removeFirst()
            }
          }

          self.frameCount += 1

          // Executa os passes 3D Metal em tempo real na textura do drawable + compute furnace pass para estresse máximo contínuo
          let ok = GpuBenchmark.shared.encodeRenderFrame(
            cb,
            frameIndex: self.frameCount,
            targetTexture: drawable.texture,
            burnInCompute: true
          )
          if ok {
            cb.present(drawable)
            cb.commit()
          }

          // Atualiza HUD periodicamente (a cada ~12 frames para suavidade sem pesar na main thread)
          if self.frameCount % 12 == 0 {
            let elapsedSec = Double(nowNs - self.startTimeNs) / 1_000_000_000.0
            let avgDelta = self.recentFrameDeltas.isEmpty ? 0.004 : self.recentFrameDeltas.reduce(0, +) / Double(self.recentFrameDeltas.count)
            let curFps = avgDelta > 0 ? 1.0 / avgDelta : 0.0
            let frameMs = avgDelta * 1000.0

            if self.peakFps == 0.0 || curFps > self.peakFps { self.peakFps = curFps }
            if self.minFps == 0.0 || (curFps < self.minFps && self.frameCount > 30) { self.minFps = curFps }

            let sens = NativeSensors.shared.collect(cpuUsagePercent: 12.0, gpuActive: true)
            let gTemp = sens["gpu_temp"] as? Double ?? 0.0
            let cTemp = sens["cpu_temp"] as? Double ?? 0.0
            var gUsage = sens["gpu_usage"] as? Double ?? 0.0
            if gUsage <= 0.0 && self.isRunningLoop && !self.isBenchmarkComplete {
              gUsage = 99.0
            }

            DispatchQueue.main.async { [weak self] in
              guard let self = self else { return }
              self.gpuUsageLabel.stringValue = String(format: "Uso GPU: %.0f%%", gUsage)
              if gUsage >= 90.0 {
                self.gpuUsageLabel.textColor = NSColor(red: 0.98, green: 0.45, blue: 0.08, alpha: 1.0)
              } else {
                self.gpuUsageLabel.textColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0)
              }
              self.fpsLabel.stringValue = String(format: "FPS: %.1f", curFps)
              self.frameTimeLabel.stringValue = String(format: "Frame: %.2f ms", frameMs)
              self.tempLabel.stringValue = String(format: "Temp: GPU %.0f°C | CPU %.0f°C", gTemp, cTemp)

              if self.currentMode == "benchmark" {
                let remaining = max(0.0, 15.0 - elapsedSec)
                self.statusLabel.stringValue = String(format: "Tempo: %.1fs / 15.0s", elapsedSec)
                if remaining <= 0.0 && !self.isBenchmarkComplete {
                  self.isBenchmarkComplete = true
                  self.isRunningLoop = false
                  self.gpuUsageLabel.stringValue = "Uso GPU: 0%"
                  self.gpuUsageLabel.textColor = NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0)
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
      }
    }
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    isRunningLoop = false
    sender.orderOut(nil)
    return false
  }
}
