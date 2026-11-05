import Foundation
import Metal
import simd

/// Benchmarks de GPU em Metal.
///
/// Dois testes independentes em 1920x1080 off-screen:
/// - **compute**: kernel pesado de FMA + sin/cos/sqrt.
/// - **render**: cena 3D real com 1.024 cubos instanciados, depth buffer,
///   iluminação difusa/especular e céu procedural. Também coleta o tempo
///   de cada frame para calcular 1% low (frame pacing).
///
/// O resultado principal é a taxa de frames por segundo medida pelo tempo
/// de GPU dos command buffers. Não usa MetalKit nem dependência externa.
final class GpuBenchmark {
  static let shared = GpuBenchmark()

  private let width = 1920
  private let height = 1080
  private let computeIterations: UInt32 = 48
  private let backgroundIterations: UInt32 = 24
  private let sceneInstances = 1024
  private let cubeTriangles = 12
  private let batchSize = 4

  private struct SceneVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
  }

  private let device: MTLDevice?
  private let queue: MTLCommandQueue?

  private let computePipeline: MTLComputePipelineState?
  private let computeOutput: MTLBuffer?

  private let backgroundPipeline: MTLRenderPipelineState?
  private let scenePipeline: MTLRenderPipelineState?
  private var skyDepthState: MTLDepthStencilState?
  private var sceneDepthState: MTLDepthStencilState?
  private let sceneVertexBuffer: MTLBuffer?
  private let renderTexture: MTLTexture?
  private let depthTexture: MTLTexture?

  private init() {
    let dev = MTLCreateSystemDefaultDevice()
    device = dev

    guard let dev = dev else {
      queue = nil
      computePipeline = nil
      computeOutput = nil
      backgroundPipeline = nil
      scenePipeline = nil
      skyDepthState = nil
      sceneDepthState = nil
      sceneVertexBuffer = nil
      renderTexture = nil
      depthTexture = nil
      return
    }

    queue = dev.makeCommandQueue()

    // Estados de profundidade: o céu sempre passa e não escreve;
    // a cena testa contra o que já foi desenhado.
    let skyDepthDescriptor = MTLDepthStencilDescriptor()
    skyDepthDescriptor.depthCompareFunction = .always
    skyDepthDescriptor.isDepthWriteEnabled = false
    skyDepthState = dev.makeDepthStencilState(descriptor: skyDepthDescriptor)

    let sceneDepthDescriptor = MTLDepthStencilDescriptor()
    sceneDepthDescriptor.depthCompareFunction = .less
    sceneDepthDescriptor.isDepthWriteEnabled = true
    sceneDepthState = dev.makeDepthStencilState(descriptor: sceneDepthDescriptor)

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
    // Céu procedural: triângulo full-screen com ruído + iluminação.
    // ---------------------------------------------------------------
    struct BmbSkyVOut {
      float4 position [[position]];
      float2 uv;
    };

    vertex BmbSkyVOut bmb_sky_vertex(uint vid [[vertex_id]]) {
      float2 p = float2((vid << 1) & 2, vid & 2);
      BmbSkyVOut o;
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

    fragment float4 bmb_sky_fragment(BmbSkyVOut in [[stage_in]],
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
      return float4(col * 0.55f, 1.0f);
    }

    // ---------------------------------------------------------------
    // Cena 3D: cubos instanciados com depth buffer e iluminação.
    // ---------------------------------------------------------------
    struct BmbSceneVertex {
      float3 position;
      float3 normal;
    };

    struct BmbSceneVOut {
      float4 position [[position]];
      float3 normal;
      float3 color;
    };

    vertex BmbSceneVOut bmb_scene_vertex(uint vid [[vertex_id]],
                                         uint iid [[instance_id]],
                                         constant float4x4 &viewProj [[buffer(0)]],
                                         constant float &time [[buffer(1)]],
                                         const device BmbSceneVertex *mesh [[buffer(2)]]) {
      BmbSceneVertex v = mesh[vid];
      float fi = float(iid);
      float gx = fmod(fi, 32.0f) - 15.5f;
      float gz = floor(fi / 32.0f) - 15.5f;
      float angle = time * 0.6f + fi * 0.13f;

      float3 base = float3(
        gx * 0.55f,
        sin(time * 1.3f + fi * 0.17f) * 1.1f,
        gz * 0.55f
      );

      float3 local = v.position * 0.34f;
      float cy = cos(angle);
      float sy = sin(angle);
      float cx = cos(angle * 0.7f);
      float sx = sin(angle * 0.7f);

      float3 p = float3(
        local.x * cy - local.z * sy,
        local.y,
        local.x * sy + local.z * cy
      );
      p = float3(p.x, p.y * cx - p.z * sx, p.y * sx + p.z * cx);
      float3 world = base + p;

      float3 n = v.normal;
      n = float3(n.x * cy - n.z * sy, n.y, n.x * sy + n.z * cy);
      n = float3(n.x, n.y * cx - n.z * sx, n.y * sx + n.z * cx);

      BmbSceneVOut o;
      o.position = viewProj * float4(world, 1.0f);
      o.normal = n;
      o.color = float3(
        0.45f + 0.45f * sin(fi * 0.37f),
        0.45f + 0.45f * sin(fi * 0.53f + 1.0f),
        0.45f + 0.45f * sin(fi * 0.71f + 2.0f)
      );
      return o;
    }

    fragment float4 bmb_scene_fragment(BmbSceneVOut in [[stage_in]],
                                       constant float3 &lightDir [[buffer(0)]]) {
      float3 n = normalize(in.normal);
      float3 l = normalize(lightDir);
      float diff = max(dot(n, l), 0.0f);
      float3 viewDir = float3(0.0f, 0.0f, 1.0f);
      float spec = pow(max(dot(reflect(-l, n), viewDir), 0.0f), 24.0f);
      float3 col = in.color * (0.25f + 0.75f * diff) + float3(0.18f) * spec;
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

      // Céu
      if let vertexFn = library.makeFunction(name: "bmb_sky_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_sky_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.colorAttachments[0].isBlendingEnabled = false
        backgroundPipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        backgroundPipeline = nil
      }

      // Cena 3D
      if let vertexFn = library.makeFunction(name: "bmb_scene_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_scene_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.colorAttachments[0].isBlendingEnabled = false
        scenePipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        scenePipeline = nil
      }

      let vertices = GpuBenchmark.makeCubeVertices()
      sceneVertexBuffer = dev.makeBuffer(
        bytes: vertices,
        length: vertices.count * MemoryLayout<SceneVertex>.stride,
        options: .storageModeShared
      )

      let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
        mipmapped: false
      )
      colorDescriptor.usage = [.renderTarget, .shaderRead]
      colorDescriptor.storageMode = .private
      renderTexture = dev.makeTexture(descriptor: colorDescriptor)

      let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float,
        width: width,
        height: height,
        mipmapped: false
      )
      depthDescriptor.usage = [.renderTarget]
      depthDescriptor.storageMode = .private
      depthTexture = dev.makeTexture(descriptor: depthDescriptor)
    } catch {
      computePipeline = nil
      computeOutput = nil
      backgroundPipeline = nil
      scenePipeline = nil
      skyDepthState = nil
      sceneDepthState = nil
      sceneVertexBuffer = nil
      renderTexture = nil
      depthTexture = nil
    }
  }

  var isComputeAvailable: Bool {
    device != nil && queue != nil && computePipeline != nil && computeOutput != nil
  }

  var isRenderAvailable: Bool {
    device != nil && queue != nil && backgroundPipeline != nil
      && scenePipeline != nil && sceneVertexBuffer != nil
      && renderTexture != nil && depthTexture != nil
      && skyDepthState != nil && sceneDepthState != nil
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
      "render_iterations": Int(backgroundIterations),
      "scene_instances": sceneInstances,
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

    let measurement = try measure(durationMs: durationMs, perFrame: false) {
      commandBuffer, _ in
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

  /// Benchmark de renderização: cena 3D com cubos instanciados, depth buffer
  /// e iluminação, medindo fps médio e frame pacing (1% low).
  func runRender(durationMs: Int) throws -> [String: Any] {
    guard let dev = device, let background = backgroundPipeline,
      let scene = scenePipeline, let mesh = sceneVertexBuffer,
      let colorTexture = renderTexture, let depth = depthTexture
    else {
      throw gpuError("Metal render indisponível neste dispositivo")
    }

    let passDescriptor = MTLRenderPassDescriptor()
    passDescriptor.colorAttachments[0].texture = colorTexture
    passDescriptor.colorAttachments[0].loadAction = .clear
    passDescriptor.colorAttachments[0].storeAction = .store
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
    passDescriptor.depthAttachment.texture = depth
    passDescriptor.depthAttachment.loadAction = .clear
    passDescriptor.depthAttachment.storeAction = .dontCare
    passDescriptor.depthAttachment.clearDepth = 1.0

    let viewProjection = makeViewProjection()
    var light = SIMD3<Float>(0.45, 0.85, 0.3)

    let measurement = try measure(durationMs: durationMs, perFrame: true) {
      commandBuffer, frameIndex in
      guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
      else {
        return false
      }

      var time = Float(frameIndex % 4096) * 0.008

      // Céu procedural (não escreve profundidade, não testa).
      if let skyDepthState = skyDepthState {
        encoder.setDepthStencilState(skyDepthState)
      }
      encoder.setRenderPipelineState(background)
      encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
      var skyIterations = backgroundIterations
      encoder.setFragmentBytes(
        &skyIterations,
        length: MemoryLayout<UInt32>.size,
        index: 1
      )
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

      // Cena 3D instanciada (testada contra a profundidade).
      if let sceneDepthState = sceneDepthState {
        encoder.setDepthStencilState(sceneDepthState)
      }
      encoder.setRenderPipelineState(scene)
      var matrix = viewProjection
      encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.stride, index: 0)
      encoder.setVertexBytes(&time, length: MemoryLayout<Float>.size, index: 1)
      encoder.setVertexBuffer(mesh, offset: 0, index: 2)
      encoder.setFragmentBytes(&light, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
      encoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 36,
        instanceCount: sceneInstances
      )

      encoder.endEncoding()
      return true
    }

    var payload = resultPayload(
      kind: "render",
      deviceName: dev.name,
      measurement: measurement,
      iterations: Int(backgroundIterations)
    )
    payload["instances"] = sceneInstances
    payload["triangles_per_frame"] = sceneInstances * cubeTriangles + 1
    payload["shading_iterations"] = Int(backgroundIterations)
    return payload
  }

  // ---------------------------------------------------------------------
  // Medição compartilhada
  // ---------------------------------------------------------------------

  private struct Measurement {
    let frames: Int
    let seconds: Double
    let gpuSeconds: Double
    let frameDurations: [Double]
  }

  private func measure(
    durationMs: Int,
    perFrame: Bool,
    encodeFrame: (MTLCommandBuffer, Int) -> Bool
  ) throws -> Measurement {
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
    let framesPerBatch = perFrame ? 1 : batchSize

    var frames = 0
    var gpuSeconds = 0.0
    var frameIndex = 0
    var frameDurations: [Double] = []
    var failed = false

    while DispatchTime.now().uptimeNanoseconds < deadline {
      guard let cb = queue.makeCommandBuffer() else {
        failed = true
        break
      }

      var batchOK = true
      for _ in 0..<framesPerBatch {
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

      frames += framesPerBatch
      let gpuDelta = cb.gpuEndTime - cb.gpuStartTime
      if gpuDelta > 0 {
        gpuSeconds += gpuDelta
        if perFrame {
          frameDurations.append(gpuDelta)
        }
      }
    }

    let wallSeconds =
      Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1_000_000_000
    let measuredSeconds = gpuSeconds > 0 ? gpuSeconds : wallSeconds

    guard !failed, frames > 0, measuredSeconds > 0 else {
      throw gpuError("A GPU não concluiu nenhum frame")
    }

    return Measurement(
      frames: frames,
      seconds: measuredSeconds,
      gpuSeconds: gpuSeconds,
      frameDurations: frameDurations
    )
  }

  private func resultPayload(
    kind: String,
    deviceName: String,
    measurement: Measurement,
    iterations: Int
  ) -> [String: Any] {
    let pixels = width * height
    let fps = Double(measurement.frames) / measurement.seconds
    let score = fps * 100.0

    var payload: [String: Any] = [
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

    if measurement.frameDurations.count >= 10 {
      let sorted = measurement.frameDurations.sorted()
      let avgMs = measurement.seconds * 1000.0 / Double(measurement.frames)
      let p99Ms = percentile(sorted, 0.99) * 1000.0
      let p999Ms = percentile(sorted, 0.999) * 1000.0

      payload["avg_frame_ms"] = (avgMs * 100).rounded() / 100
      payload["p99_frame_ms"] = (p99Ms * 100).rounded() / 100
      payload["p999_frame_ms"] = (p999Ms * 100).rounded() / 100
      payload["one_percent_low_fps"] = (1000.0 / p99Ms * 100).rounded() / 100
      payload["point_one_percent_low_fps"] =
        (1000.0 / p999Ms * 100).rounded() / 100
      payload["frame_time_samples"] = sorted.count
    }

    return payload
  }

  private func percentile(_ sorted: [Double], _ q: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * q)) - 1))
    return sorted[index]
  }

  // ---------------------------------------------------------------------
  // Geometria e câmera
  // ---------------------------------------------------------------------

  private static func makeCubeVertices() -> [SceneVertex] {
    let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
      (
        SIMD3(1, 0, 0),
        [
          SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, 0.5, -0.5),
          SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, -0.5, 0.5),
        ]
      ),
      (
        SIMD3(-1, 0, 0),
        [
          SIMD3(-0.5, -0.5, 0.5), SIMD3(-0.5, 0.5, 0.5),
          SIMD3(-0.5, 0.5, -0.5), SIMD3(-0.5, -0.5, -0.5),
        ]
      ),
      (
        SIMD3(0, 1, 0),
        [
          SIMD3(-0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, 0.5),
          SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, 0.5, -0.5),
        ]
      ),
      (
        SIMD3(0, -1, 0),
        [
          SIMD3(-0.5, -0.5, 0.5), SIMD3(-0.5, -0.5, -0.5),
          SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, -0.5, 0.5),
        ]
      ),
      (
        SIMD3(0, 0, 1),
        [
          SIMD3(-0.5, -0.5, 0.5), SIMD3(0.5, -0.5, 0.5),
          SIMD3(0.5, 0.5, 0.5), SIMD3(-0.5, 0.5, 0.5),
        ]
      ),
      (
        SIMD3(0, 0, -1),
        [
          SIMD3(0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, -0.5),
          SIMD3(-0.5, 0.5, -0.5), SIMD3(0.5, 0.5, -0.5),
        ]
      ),
    ]

    var vertices: [SceneVertex] = []
    vertices.reserveCapacity(36)
    for (normal, corners) in faces {
      for index in [0, 1, 2, 0, 2, 3] {
        vertices.append(SceneVertex(position: corners[index], normal: normal))
      }
    }
    return vertices
  }

  private func makeViewProjection() -> simd_float4x4 {
    let eye = SIMD3<Float>(0, 8.5, 22)
    let center = SIMD3<Float>(0, 0.5, 0)
    let up = SIMD3<Float>(0, 1, 0)
    let forward = simd_normalize(center - eye)
    let right = simd_normalize(simd_cross(forward, up))
    let trueUp = simd_cross(right, forward)

    let view = simd_float4x4(
      SIMD4<Float>(right.x, trueUp.x, -forward.x, 0),
      SIMD4<Float>(right.y, trueUp.y, -forward.y, 0),
      SIMD4<Float>(right.z, trueUp.z, -forward.z, 0),
      SIMD4<Float>(
        -simd_dot(right, eye),
        -simd_dot(trueUp, eye),
        simd_dot(forward, eye),
        1
      )
    )

    let fov = Float(55.0 * Double.pi / 180.0)
    let aspect = Float(width) / Float(height)
    let ys = 1.0 / tan(fov / 2.0)
    let xs = ys / aspect
    let near: Float = 0.1
    let far: Float = 120.0
    let zs = far / (near - far)

    let projection = simd_float4x4(
      SIMD4<Float>(xs, 0, 0, 0),
      SIMD4<Float>(0, ys, 0, 0),
      SIMD4<Float>(0, 0, zs, -1),
      SIMD4<Float>(0, 0, zs * near, 0)
    )

    return projection * view
  }

  private func gpuError(_ message: String) -> NSError {
    NSError(
      domain: "bemybench.gpu",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
