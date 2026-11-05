import Foundation
import Metal

/// Benchmark de GPU em Metal.
///
/// Executa um kernel de compute pesado (FMA + sin/cos/sqrt) sobre uma
/// "imagem" off-screen de 1920x1080 por vários frames. O resultado é a
/// taxa de frames processados por segundo, que vira o score próprio do
/// BMyBench. Não usa MetalKit nem nenhuma dependência externa.
final class GpuBenchmark {
  static let shared = GpuBenchmark()

  private let width = 1920
  private let height = 1080
  private let iterations: UInt32 = 48
  private let batchSize = 4

  private let device: MTLDevice?
  private let queue: MTLCommandQueue?
  private let pipeline: MTLComputePipelineState?
  private let outputBuffer: MTLBuffer?

  private init() {
    let dev = MTLCreateSystemDefaultDevice()
    device = dev

    guard let dev = dev else {
      queue = nil
      pipeline = nil
      outputBuffer = nil
      return
    }

    queue = dev.makeCommandQueue()

    let source = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void bmb_gpu_kernel(device float4 *out [[buffer(0)]],
                               constant uint &iterations [[buffer(1)]],
                               uint id [[thread_position_in_grid]]) {
      float4 v = float4((float)id * 0.000001f, 1.0f, 2.0f, 3.0f);
      float4 acc = float4(0.0f);
      for (uint i = 0; i < iterations; ++i) {
        v = v * 1.0000001f + float4(0.000001f);
        float4 s = sin(v);
        float4 c = cos(v.yzwx);
        v = s * c + sqrt(abs(v));
        acc += v;
      }
      out[id] = acc;
    }
    """

    do {
      let library = try dev.makeLibrary(source: source, options: nil)
      guard let function = library.makeFunction(name: "bmb_gpu_kernel") else {
        pipeline = nil
        outputBuffer = nil
        return
      }
      pipeline = try dev.makeComputePipelineState(function: function)
      let pixels = width * height
      outputBuffer = dev.makeBuffer(
        length: pixels * MemoryLayout<SIMD4<Float>>.stride,
        options: .storageModePrivate
      )
    } catch {
      pipeline = nil
      outputBuffer = nil
    }
  }

  var isAvailable: Bool {
    device != nil && queue != nil && pipeline != nil && outputBuffer != nil
  }

  /// Informações da GPU para exibir na UI.
  func info() -> [String: Any] {
    guard let dev = device else {
      return [
        "available": false,
        "reason": "Metal indisponível neste dispositivo",
      ]
    }

    return [
      "available": isAvailable,
      "name": dev.name,
      "unified_memory": dev.hasUnifiedMemory,
      "recommended_working_set_mb": Int(dev.recommendedMaxWorkingSetSize / (1024 * 1024)),
      "max_threads_per_group": pipeline?.maxTotalThreadsPerThreadgroup ?? 0,
      "width": width,
      "height": height,
      "iterations": Int(iterations),
    ]
  }

  /// Roda o benchmark por aproximadamente `durationMs` milissegundos.
  func run(durationMs: Int) throws -> [String: Any] {
    guard let dev = device,
      let queue = queue,
      let pipeline = pipeline,
      let output = outputBuffer
    else {
      throw NSError(
        domain: "bemybench.gpu",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Metal indisponível neste dispositivo"]
      )
    }

    let pixels = width * height
    let grid = MTLSize(width: pixels, height: 1, depth: 1)
    let threadgroupWidth = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
    let threadgroup = MTLSize(width: threadgroupWidth, height: 1, depth: 1)

    func encodeFrame(_ commandBuffer: MTLCommandBuffer) {
      guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
      encoder.setComputePipelineState(pipeline)
      encoder.setBuffer(output, offset: 0, index: 0)
      var iters = iterations
      encoder.setBytes(&iters, length: MemoryLayout<UInt32>.size, index: 1)
      encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
      encoder.endEncoding()
    }

    // Aquecimento: compila o pipeline e estabiliza o clock da GPU.
    for _ in 0..<2 {
      guard let cb = queue.makeCommandBuffer() else { continue }
      encodeFrame(cb)
      cb.commit()
      cb.waitUntilCompleted()
    }

    let targetMs = max(500, durationMs)
    let wallStart = DispatchTime.now().uptimeNanoseconds
    let deadline = wallStart + UInt64(targetMs) * 1_000_000

    var frames = 0
    var gpuSeconds = 0.0
    var failed = false

    while DispatchTime.now().uptimeNanoseconds < deadline {
      guard let cb = queue.makeCommandBuffer() else {
        failed = true
        break
      }
      for _ in 0..<batchSize {
        encodeFrame(cb)
      }
      cb.commit()
      cb.waitUntilCompleted()

      if cb.status != .completed {
        failed = true
        break
      }

      frames += batchSize
      let gpuDelta = cb.gpuEndTime - cb.gpuStartTime
      if gpuDelta > 0 {
        gpuSeconds += gpuDelta
      }
    }

    let wallSeconds =
      Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1_000_000_000
    let measuredSeconds = gpuSeconds > 0 ? gpuSeconds : wallSeconds

    guard !failed, frames > 0, measuredSeconds > 0 else {
      throw NSError(
        domain: "bemybench.gpu",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "A GPU não concluiu nenhum frame"]
      )
    }

    let fps = Double(frames) / measuredSeconds
    // Score próprio: frames/s x 100. É apenas uma escala de apresentação;
    // a comparação com outras suítes usa conversão calibrada.
    let score = fps * 100.0
    let pixelsPerSecond = fps * Double(pixels)

    return [
      "available": true,
      "device": dev.name,
      "width": width,
      "height": height,
      "iterations": Int(iterations),
      "frames": frames,
      "elapsed_ms": (measuredSeconds * 1000).rounded(),
      "fps": (fps * 100).rounded() / 100,
      "pixels_per_second": pixelsPerSecond.rounded(),
      "score": (score * 10).rounded() / 10,
      "gpu_time_used": gpuSeconds > 0,
    ]
  }
}
