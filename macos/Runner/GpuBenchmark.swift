import Foundation
import Metal

/// Benchmarks de GPU em Metal.
///
/// Dois testes independentes, ambos off-screen em 1920x1080:
/// - **compute**: kernel pesado de FMA + sin/cos/sqrt.
/// - **render**: pipeline gráfico real (vertex + fragment shader) com
///   ruído procedural e iluminação, exercitando rasterização e fill rate.
///
/// O resultado é a taxa de frames por segundo medida pelo tempo de GPU
/// dos command buffers. Não usa MetalKit nem dependência externa.
final class GpuBenchmark {
  static let shared = GpuBenchmark()

  private let width = 1920
  private let height = 1080
  private let computeIterations: UInt32 = 48
  private let renderIterations: UInt32 = 24
  private let batchSize = 4

  private let device: MTLDevice?
  private let queue: MTLCommandQueue?

  private let computePipeline: MTLComputePipelineState?
  private let computeOutput: MTLBuffer?

  private let renderPipeline: MTLRenderPipelineState?
  private let renderTexture: MTLTexture?

  private init() {
    let dev = MTLCreateSystemDefaultDevice()
    device = dev

    guard let dev = dev else {
      queue = nil
      computePipeline = nil
      computeOutput = nil
      renderPipeline = nil
      renderTexture = nil
      return
    }

    queue = dev.makeCommandQueue()

    let source = """
    #include <metal_stdlib>
    using namespace metal;

    // ---------------------------------------------------------------
    // Compute: operações escalares/vetoriais densas por pixel.
    // ---------------------------------------------------------------
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

    // ---------------------------------------------------------------
    // Render: triângulo full-screen com fragment shader procedural.
    // Simula o custo de shading/fill rate típico de um frame de jogo.
    // ---------------------------------------------------------------
    struct BmbVOut {
      float4 position [[position]];
      float2 uv;
    };

    vertex BmbVOut bmb_render_vertex(uint vid [[vertex_id]]) {
      float2 p = float2((vid << 1) & 2, vid & 2);
      BmbVOut o;
      o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
      o.uv = p;
      return o;
    }

    static float bmb_hash(float2 p) {
      p = fract(p * float2(123.34f, 456.21f));
      p += dot(p, p + 45.32f);
      return fract(p.x * p.y);
    }

    static float bmb_noise(float2 p) {
      float2 i = floor(p);
      float2 f = fract(p);
      float a = bmb_hash(i);
      float b = bmb_hash(i + float2(1.0f, 0.0f));
      float c = bmb_hash(i + float2(0.0f, 1.0f));
      float d = bmb_hash(i + float2(1.0f, 1.0f));
      float2 u = f * f * (3.0f - 2.0f * f);
      return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    fragment float4 bmb_render_fragment(BmbVOut in [[stage_in]],
                                        constant float &time [[buffer(0)]],
                                        constant uint &iterations [[buffer(1)]]) {
      float2 uv = in.uv;
      float2 p = uv * 8.0f + time * 0.05f;
      float3 col = float3(0.0f);
      float acc = 0.0f;

      for (uint i = 0; i < iterations; ++i) {
        float fi = float(i);
        p = float2(p.x * 1.17f + fi * 0.13f, p.y * 1.11f - fi * 0.09f);
        float n = bmb_noise(p);
        float m = bmb_noise(p * 2.3f + n);
        acc += (n + m) / (1.0f + fi);
        col += float3(n * 0.9f, m * 0.6f + 0.1f, (n + m) * 0.5f) / (1.0f + fi);
      }

      col += float3(
        sin(uv.x * 60.0f + time),
        cos(uv.y * 54.0f - time),
        sin((uv.x + uv.y) * 40.0f)
      ) * 0.15f;

      col = col / (1.0f + acc * 0.15f);
      return float4(col, 1.0f);
    }
    """

    do {
      let library = try dev.makeLibrary(source: source, options: nil)

      // Compute
      if let function = library.makeFunction(name: "bmb_gpu_kernel") {
        computePipeline = try? dev.makeComputePipelineState(function: function)
      } else {
        computePipeline = nil
      }
      let pixels = width * height
      computeOutput = dev.makeBuffer(
        length: pixels * MemoryLayout<SIMD4<Float>>.stride,
        options: .storageModePrivate
      )

      // Render
      if let vertexFn = library.makeFunction(name: "bmb_render_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_render_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        renderPipeline = nil
      }

      let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
        mipmapped: false
      )
      textureDescriptor.usage = [.renderTarget, .shaderRead]
      textureDescriptor.storageMode = .private
      renderTexture = dev.makeTexture(descriptor: textureDescriptor)
    } catch {
      computePipeline = nil
      computeOutput = nil
      renderPipeline = nil
      renderTexture = nil
    }
  }

  var isComputeAvailable: Bool {
    device != nil && queue != nil && computePipeline != nil && computeOutput != nil
  }

  var isRenderAvailable: Bool {
    device != nil && queue != nil && renderPipeline != nil && renderTexture != nil
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
      "available": isComputeAvailable,
      "render_available": isRenderAvailable,
      "name": dev.name,
      "unified_memory": dev.hasUnifiedMemory,
      "recommended_working_set_mb": Int(dev.recommendedMaxWorkingSetSize / (1024 * 1024)),
      "max_threads_per_group": computePipeline?.maxTotalThreadsPerThreadgroup ?? 0,
      "width": width,
      "height": height,
      "iterations": Int(computeIterations),
      "render_iterations": Int(renderIterations),
    ]
  }

  /// Benchmark de compute (FMA + sin/cos/sqrt).
  func runCompute(durationMs: Int) throws -> [String: Any] {
    guard let dev = device, let pipeline = computePipeline, let output = computeOutput
    else {
      throw gpuError("Metal compute indisponível neste dispositivo")
    }

    let pixels = width * height
    let grid = MTLSize(width: pixels, height: 1, depth: 1)
    let threadgroupWidth = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
    let threadgroup = MTLSize(width: threadgroupWidth, height: 1, depth: 1)

    let measurement = try measure(durationMs: durationMs) { commandBuffer, _ in
      guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
        return false
      }
      encoder.setComputePipelineState(pipeline)
      encoder.setBuffer(output, offset: 0, index: 0)
      var iters = computeIterations
      encoder.setBytes(&iters, length: MemoryLayout<UInt32>.size, index: 1)
      encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
      encoder.endEncoding()
      return true
    }

    return resultPayload(
      kind: "compute",
      deviceName: dev.name,
      measurement: measurement,
      iterations: Int(computeIterations)
    )
  }

  /// Benchmark de renderização: pipeline gráfico off-screen com fragment
  /// shader procedural (ruído + iluminação), medindo fill rate/shading.
  func runRender(durationMs: Int) throws -> [String: Any] {
    guard let dev = device, let pipeline = renderPipeline, let texture = renderTexture
    else {
      throw gpuError("Metal render indisponível neste dispositivo")
    }

    let passDescriptor = MTLRenderPassDescriptor()
    passDescriptor.colorAttachments[0].texture = texture
    passDescriptor.colorAttachments[0].loadAction = .clear
    passDescriptor.colorAttachments[0].storeAction = .store
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

    let measurement = try measure(durationMs: durationMs) { commandBuffer, frameIndex in
      guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
      else {
        return false
      }
      encoder.setRenderPipelineState(pipeline)
      var time = Float(frameIndex % 2048) * 0.01
      encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
      var iters = renderIterations
      encoder.setFragmentBytes(&iters, length: MemoryLayout<UInt32>.size, index: 1)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
      encoder.endEncoding()
      return true
    }

    var payload = resultPayload(
      kind: "render",
      deviceName: dev.name,
      measurement: measurement,
      iterations: Int(renderIterations)
    )
    payload["triangles_per_frame"] = 1
    payload["shading_iterations"] = Int(renderIterations)
    return payload
  }

  // ---------------------------------------------------------------------
  // Medição compartilhada
  // ---------------------------------------------------------------------

  private func measure(
    durationMs: Int,
    encodeFrame: (MTLCommandBuffer, Int) -> Bool
  ) throws -> (frames: Int, seconds: Double, gpuSeconds: Double) {
    guard let queue = queue else {
      throw gpuError("Command queue indisponível")
    }

    // Aquecimento: compila pipelines e estabiliza o clock da GPU.
    for i in 0..<2 {
      guard let cb = queue.makeCommandBuffer() else { continue }
      _ = encodeFrame(cb, i)
      cb.commit()
      cb.waitUntilCompleted()
    }

    let targetMs = max(500, durationMs)
    let wallStart = DispatchTime.now().uptimeNanoseconds
    let deadline = wallStart + UInt64(targetMs) * 1_000_000

    var frames = 0
    var gpuSeconds = 0.0
    var frameIndex = 0
    var failed = false

    while DispatchTime.now().uptimeNanoseconds < deadline {
      guard let cb = queue.makeCommandBuffer() else {
        failed = true
        break
      }

      var batchOK = true
      for _ in 0..<batchSize {
        if !encodeFrame(cb, frameIndex) {
          batchOK = false
          break
        }
        frameIndex += 1
      }

      if !batchOK {
        failed = true
        break
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
      throw gpuError("A GPU não concluiu nenhum frame")
    }

    return (frames, measuredSeconds, gpuSeconds)
  }

  private func resultPayload(
    kind: String,
    deviceName: String,
    measurement: (frames: Int, seconds: Double, gpuSeconds: Double),
    iterations: Int
  ) -> [String: Any] {
    let pixels = width * height
    let fps = Double(measurement.frames) / measurement.seconds
    let score = fps * 100.0
    return [
      "available": true,
      "kind": kind,
      "device": deviceName,
      "width": width,
      "height": height,
      "iterations": iterations,
      "frames": measurement.frames,
      "elapsed_ms": (measurement.seconds * 1000).rounded(),
      "fps": (fps * 100).rounded() / 100,
      "pixels_per_second": (fps * Double(pixels)).rounded(),
      "score": (score * 10).rounded() / 10,
      "gpu_time_used": measurement.gpuSeconds > 0,
    ]
  }

  private func gpuError(_ message: String) -> NSError {
    NSError(
      domain: "bemybench.gpu",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
