import Foundation
import Metal
import simd

/// Benchmarks de GPU em Metal.
///
/// Dois testes independentes em 1920x1080 off-screen:
/// - **compute**: kernel pesado de FMA + sin/cos/sqrt.
/// - **render**: cena 3D em MSAA 4x e HDR (rgba16Float), com depth buffer,
///   iluminação difusa/especular, céu procedural, bloom (bright + blur
///   separável) e tonemap ACES. Coleta o tempo de cada frame para calcular
///   1% low (frame pacing).
///
/// O resultado principal é a taxa de frames por segundo medida pelo tempo
/// de GPU dos command buffers. Não usa MetalKit nem dependência externa.
final class GpuBenchmark {
  static let shared = GpuBenchmark()

  private let width = 1920
  private let height = 1080
  private let computeIterations: UInt32 = 64
  private let backgroundIterations: UInt32 = 64
  private let sceneInstances = 16384
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

  // Render: MSAA 4x em HDR -> resolve -> bloom (bright + 2 blur) -> ACES -> LDR.
  private let backgroundPipeline: MTLRenderPipelineState?
  private let scenePipeline: MTLRenderPipelineState?
  private let brightPipeline: MTLRenderPipelineState?
  private let blurPipeline: MTLRenderPipelineState?
  private let compositePipeline: MTLRenderPipelineState?
  private var skyDepthState: MTLDepthStencilState?
  private var sceneDepthState: MTLDepthStencilState?
  private let sceneVertexBuffer: MTLBuffer?
  private let msaaColorTexture: MTLTexture?
  private let msaaDepthTexture: MTLTexture?
  private let hdrTexture: MTLTexture?
  private let bloomHalfTexture: MTLTexture?
  private let bloomBlurATexture: MTLTexture?
  private let bloomBlurBTexture: MTLTexture?
  private let finalTexture: MTLTexture?
  private let sampler: MTLSamplerState?

  private init() {
    let dev = MTLCreateSystemDefaultDevice()
    device = dev

    guard let dev = dev else {
      queue = nil
      computePipeline = nil
      computeOutput = nil
      backgroundPipeline = nil
      scenePipeline = nil
      brightPipeline = nil
      blurPipeline = nil
      compositePipeline = nil
      skyDepthState = nil
      sceneDepthState = nil
      sceneVertexBuffer = nil
      msaaColorTexture = nil
      msaaDepthTexture = nil
      hdrTexture = nil
      bloomHalfTexture = nil
      bloomBlurATexture = nil
      bloomBlurBTexture = nil
      finalTexture = nil
      sampler = nil
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

    static float bmb_fbm(float2 p) {
      float v = 0.0f;
      float a = 0.5f;
      float2 shift = float2(100.0f);
      float2x2 rot = float2x2(cos(0.5f), sin(0.5f), -sin(0.5f), cos(0.5f));
      for (int i = 0; i < 8; ++i) {
        v += a * bmb_noise(p);
        p = rot * p * 2.05f + shift;
        a *= 0.5f;
      }
      return v;
    }

    fragment float4 bmb_sky_fragment(BmbSkyVOut in [[stage_in]],
                                     constant float &time [[buffer(0)]],
                                     constant uint &iterations [[buffer(1)]]) {
      float2 uv = in.uv;
      float2 p = uv * 5.0f + float2(time * 0.08f, -time * 0.12f);
      float smoke = bmb_fbm(p);
      float smokeDetail = bmb_fbm(p * 2.2f + float2(time * 0.05f, 0.0f));

      // Vignette suave circular: escurece as bordas, focando no donut
      float2 centerOffset = uv - 0.5f;
      float dist = length(centerOffset);
      float vignette = clamp(1.0f - dist * 1.15f, 0.0f, 1.0f);

      // Fundo carvão escuro com brasas e névoa vulcânica densa (fBm pesado em todos os pixels)
      float3 bgDark = float3(0.04f, 0.045f, 0.06f);
      float3 bgEmber = float3(0.22f, 0.08f, 0.02f);
      float3 col = mix(bgDark, bgEmber, smoke * 0.85f + smokeDetail * 0.35f) * vignette;

      // Partículas de brasa incandescentes
      float2 emberP = uv * 32.0f + float2(sin(uv.y * 12.0f + time), -time * 2.2f);
      float ember = pow(bmb_noise(emberP), 8.0f) * 1.8f;
      col += float3(1.35f, 0.55f, 0.08f) * ember * (1.0f - dist);

      return float4(col, 1.0f);
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
      float3 worldPos;
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
      float ringSteps = 128.0f;
      float tubeSteps = 128.0f; // 128 * 128 = 16384 instances
      float angleRing = fmod(fi, ringSteps) * (6.2831853f / ringSteps) + time * 0.75f;
      float angleTube = floor(fi / ringSteps) * (6.2831853f / tubeSteps) + time * 1.35f;

      // FurMark Torus geometry (Donut denso, espesso e contínuo)
      float R = 7.2f;
      float r = 3.2f + 0.45f * sin(angleRing * 4.0f + time * 2.2f);

      float3 base = float3(
        (R + r * cos(angleTube)) * cos(angleRing),
        r * sin(angleTube),
        (R + r * cos(angleTube)) * sin(angleRing)
      );

      // Normal radial do tubo
      float3 tubeNormal = float3(
        cos(angleTube) * cos(angleRing),
        sin(angleTube),
        cos(angleTube) * sin(angleRing)
      );

      // Cerdas espessas sobrepostas sem lacunas para formar pelagem contínua FurMark
      float3 local = v.position * float3(0.48f, 0.88f, 0.48f);
      float angle = time * 1.2f + fi * 0.05f;
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
      float3 world = base + p + tubeNormal * (0.35f + 0.25f * sin(fi * 0.15f + time * 2.5f));

      float3 n = normalize(tubeNormal * 0.7f + v.normal * 0.3f);

      BmbSceneVOut o;
      o.position = viewProj * float4(world, 1.0f);
      o.worldPos = world;
      o.normal = n;

      float heat = 0.5f + 0.5f * sin(fi * 0.08f + time * 1.5f);
      o.color = float3(heat, angleTube, angleRing);
      return o;
    }

    fragment float4 bmb_scene_fragment(BmbSceneVOut in [[stage_in]],
                                       constant float3 &lightDir [[buffer(0)]]) {
      float3 n = normalize(in.normal);
      float3 l = normalize(lightDir);
      float diff = max(dot(n, l), 0.0f);
      float3 viewDir = float3(0.0f, 0.0f, 1.0f);
      float3 h = normalize(l + viewDir);
      float spec = pow(max(dot(n, h), 0.0f), 28.0f);

      // Carga ultra-pesada FurMark (torture test): 160 passos de turbulência fractal 3D e raymarching de pelagem
      float3 p = in.worldPos * 1.35f;
      float fur = 0.0f;
      float occlusion = 1.0f;
      for (int i = 0; i < 160; ++i) {
        float fi = float(i);
        float3 s = sin(p * (1.18f + fi * 0.065f));
        float3 c = cos(p.zxy * (1.12f + fi * 0.055f));
        p = fma(s, c, p * 0.48f);
        fur += abs(dot(s, c)) / (1.0f + fi * 0.28f);
        occlusion *= 0.985f;
      }

      // Paleta FurMark autêntica (Magma vivo incandescente):
      // Núcleo / cavidades escuras de carmesim profundo
      float3 darkCore = float3(0.24f, 0.025f, 0.005f);
      // Fogo laranja intenso nas cerdas do meio
      float3 flameOrange = float3(1.35f, 0.45f, 0.02f);
      // Ouro brilhante nas pontas mais incandescentes
      float3 goldSparks = float3(1.65f, 0.98f, 0.12f);

      float furFactor = clamp((fur - 0.4f) * 0.38f, 0.0f, 1.0f);
      float3 furCol = mix(darkCore, flameOrange, furFactor);
      furCol = mix(furCol, goldSparks, pow(furFactor, 3.5f));

      // Iluminação com self-shadowing volumétrico profundo
      float3 fiery = furCol * (0.28f + 0.88f * diff * occlusion);

      // Specular quente dourado
      float3 goldenSpec = float3(1.3f, 0.82f, 0.18f) * spec * 1.5f;

      float3 col = fiery + goldenSpec;
      return float4(col, 1.0f);
    }

    // ---------------------------------------------------------------
    // Pós-processamento HDR: bloom (bright + blur) e ACES tonemap.
    // ---------------------------------------------------------------
    struct BmbPostVOut {
      float4 position [[position]];
      float2 uv;
    };

    vertex BmbPostVOut bmb_post_vertex(uint vid [[vertex_id]]) {
      float2 p = float2((vid << 1) & 2, vid & 2);
      BmbPostVOut o;
      o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
      o.uv = p;
      return o;
    }

    // Bright pass: extrai apenas o que está acima do threshold (HDR > 1).
    fragment float4 bmb_bright_fragment(BmbPostVOut in [[stage_in]],
                                       texture2d<float> scene [[texture(0)]],
                                       sampler samp [[sampler(0)]]) {
      float3 c = scene.sample(samp, in.uv).rgb;
      float lum = dot(c, float3(0.299f, 0.587f, 0.114f));
      float contribution = max(lum - 0.95f, 0.0f);
      return float4(c * contribution * 0.65f, 1.0f);
    }

    // Blur separável (5 taps com pesos de Gauss, dois offsets).
    fragment float4 bmb_blur_fragment(BmbPostVOut in [[stage_in]],
                                      texture2d<float> input [[texture(0)]],
                                      sampler samp [[sampler(0)]],
                                      constant float2 &direction [[buffer(0)]]) {
      float3 result = input.sample(samp, in.uv).rgb * 0.227027f;
      result += input.sample(samp, in.uv + direction * 1.3846154f).rgb * 0.315216f;
      result += input.sample(samp, in.uv - direction * 1.3846154f).rgb * 0.315216f;
      result += input.sample(samp, in.uv + direction * 3.2307692f).rgb * 0.070270f;
      result += input.sample(samp, in.uv - direction * 3.2307692f).rgb * 0.070270f;
      return float4(result, 1.0f);
    }

    static float3 bmb_aces(float3 x) {
      const float a = 2.51f, b = 0.03f, c = 2.43f, d = 0.59f, e = 0.14f;
      return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
    }

    fragment float4 bmb_composite_fragment(BmbPostVOut in [[stage_in]],
                                           texture2d<float> scene [[texture(0)]],
                                           texture2d<float> bloom [[texture(1)]],
                                           sampler samp [[sampler(0)]]) {
      float3 hdr = scene.sample(samp, in.uv).rgb;
      float3 bloomCol = bloom.sample(samp, in.uv).rgb;
      float3 color = hdr + bloomCol * 0.4f;
      color = bmb_aces(color);
      color = pow(color, float3(1.0f / 2.2f));
      return float4(color, 1.0f);
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

      // Céu (HDR, MSAA 4x)
      if let vertexFn = library.makeFunction(name: "bmb_sky_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_sky_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.colorAttachments[0].isBlendingEnabled = false
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = 4
        backgroundPipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        backgroundPipeline = nil
      }

      // Cena 3D (HDR, MSAA 4x)
      if let vertexFn = library.makeFunction(name: "bmb_scene_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_scene_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.colorAttachments[0].isBlendingEnabled = false
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = 4
        scenePipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        scenePipeline = nil
      }

      // Bright pass (bloom)
      if let vertexFn = library.makeFunction(name: "bmb_post_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_bright_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        brightPipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        brightPipeline = nil
      }

      // Blur separável (bloom)
      if let vertexFn = library.makeFunction(name: "bmb_post_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_blur_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        blurPipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        blurPipeline = nil
      }

      // Composite (ACES + bloom)
      if let vertexFn = library.makeFunction(name: "bmb_post_vertex"),
        let fragmentFn = library.makeFunction(name: "bmb_composite_fragment")
      {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        compositePipeline = try? dev.makeRenderPipelineState(descriptor: descriptor)
      } else {
        compositePipeline = nil
      }

      let vertices = GpuBenchmark.makeCubeVertices()
      sceneVertexBuffer = dev.makeBuffer(
        bytes: vertices,
        length: vertices.count * MemoryLayout<SceneVertex>.stride,
        options: .storageModeShared
      )

      let msaaColorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float,
        width: width,
        height: height,
        mipmapped: false
      )
      msaaColorDescriptor.sampleCount = 4
      msaaColorDescriptor.textureType = .type2DMultisample
      msaaColorDescriptor.usage = [.renderTarget]
      msaaColorDescriptor.storageMode = .private
      msaaColorTexture = dev.makeTexture(descriptor: msaaColorDescriptor)

      let msaaDepthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float,
        width: width,
        height: height,
        mipmapped: false
      )
      msaaDepthDescriptor.sampleCount = 4
      msaaDepthDescriptor.textureType = .type2DMultisample
      msaaDepthDescriptor.usage = [.renderTarget]
      msaaDepthDescriptor.storageMode = .private
      msaaDepthTexture = dev.makeTexture(descriptor: msaaDepthDescriptor)

      let hdrDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float,
        width: width,
        height: height,
        mipmapped: false
      )
      hdrDescriptor.usage = [.renderTarget, .shaderRead]
      hdrDescriptor.storageMode = .private
      hdrTexture = dev.makeTexture(descriptor: hdrDescriptor)

      let halfWidth = width / 2
      let halfHeight = height / 2
      let bloomDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float,
        width: halfWidth,
        height: halfHeight,
        mipmapped: false
      )
      bloomDescriptor.usage = [.renderTarget, .shaderRead]
      bloomDescriptor.storageMode = .private
      bloomHalfTexture = dev.makeTexture(descriptor: bloomDescriptor)
      bloomBlurATexture = dev.makeTexture(descriptor: bloomDescriptor)
      bloomBlurBTexture = dev.makeTexture(descriptor: bloomDescriptor)

      let finalDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
        mipmapped: false
      )
      finalDescriptor.usage = [.renderTarget]
      finalDescriptor.storageMode = .private
      finalTexture = dev.makeTexture(descriptor: finalDescriptor)

      let samplerDescriptor = MTLSamplerDescriptor()
      samplerDescriptor.minFilter = .linear
      samplerDescriptor.magFilter = .linear
      samplerDescriptor.mipFilter = .notMipmapped
      samplerDescriptor.sAddressMode = .clampToEdge
      samplerDescriptor.tAddressMode = .clampToEdge
      sampler = dev.makeSamplerState(descriptor: samplerDescriptor)
    } catch {
      computePipeline = nil
      computeOutput = nil
      backgroundPipeline = nil
      scenePipeline = nil
      brightPipeline = nil
      blurPipeline = nil
      compositePipeline = nil
      sceneVertexBuffer = nil
      msaaColorTexture = nil
      msaaDepthTexture = nil
      hdrTexture = nil
      bloomHalfTexture = nil
      bloomBlurATexture = nil
      bloomBlurBTexture = nil
      finalTexture = nil
      sampler = nil
    }
  }

  var isComputeAvailable: Bool {
    device != nil && queue != nil && computePipeline != nil && computeOutput != nil
  }

  var isRenderAvailable: Bool {
    device != nil && queue != nil && backgroundPipeline != nil
      && scenePipeline != nil && brightPipeline != nil
      && blurPipeline != nil && compositePipeline != nil
      && sceneVertexBuffer != nil && msaaColorTexture != nil
      && msaaDepthTexture != nil && hdrTexture != nil
      && bloomHalfTexture != nil && bloomBlurATexture != nil
      && bloomBlurBTexture != nil && finalTexture != nil
      && sampler != nil && skyDepthState != nil && sceneDepthState != nil
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
      "hdr": true,
      "msaa_samples": 4,
      "bloom": true,
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

  /// Benchmark de renderização: cena 3D em MSAA 4x e HDR, com bloom
  /// (bright + blur) e tonemap ACES no passe final. Mede fps médio e
  /// frame pacing (1% low).
  func runRender(durationMs: Int) throws -> [String: Any] {
    guard isRenderAvailable, let dev = device else {
      throw gpuError("Metal render indisponível neste dispositivo")
    }

    let measurement = try measure(durationMs: durationMs, perFrame: true) {
      commandBuffer, frameIndex in
      self.encodeRenderFrame(commandBuffer, frameIndex: frameIndex, burnInCompute: true)
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
    payload["msaa_samples"] = 4
    payload["hdr"] = true
    payload["bloom"] = true
    payload["passes"] = 5
    return payload
  }

  var metalDevice: MTLDevice? { device }
  var commandQueue: MTLCommandQueue? { queue }

  func encodeRenderFrame(
    _ commandBuffer: MTLCommandBuffer,
    frameIndex: Int,
    targetTexture: MTLTexture? = nil,
    burnInCompute: Bool = false
  ) -> Bool {
    guard let background = backgroundPipeline,
      let scene = scenePipeline,
      let bright = brightPipeline,
      let blur = blurPipeline,
      let composite = compositePipeline,
      let mesh = sceneVertexBuffer,
      let msaaColor = msaaColorTexture,
      let msaaDepth = msaaDepthTexture,
      let hdr = hdrTexture,
      let bloomHalf = bloomHalfTexture,
      let bloomBlurA = bloomBlurATexture,
      let bloomBlurB = bloomBlurBTexture,
      let final = finalTexture,
      let sampler = sampler
    else {
      return false
    }

    // Furnace Compute Pass: satura continuamente os shaders/ALU da GPU eliminando ociosidade de VSync
    if burnInCompute,
       let computePipeline = computePipeline,
       let computeOutput = computeOutput {
      if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setBuffer(computeOutput, offset: 0, index: 0)
        var iters: UInt32 = 480
        computeEncoder.setBytes(&iters, length: MemoryLayout<UInt32>.size, index: 1)
        let pixels = width * height
        let grid = MTLSize(width: pixels, height: 1, depth: 1)
        let threadgroup = MTLSize(width: min(computePipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
        computeEncoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
        computeEncoder.endEncoding()
      }
    }

    // Passe HDR (MSAA -> resolve)
    let scenePass = MTLRenderPassDescriptor()
    scenePass.colorAttachments[0].texture = msaaColor
    scenePass.colorAttachments[0].loadAction = .clear
    scenePass.colorAttachments[0].storeAction = .multisampleResolve
    scenePass.colorAttachments[0].resolveTexture = hdr
    scenePass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
    scenePass.depthAttachment.texture = msaaDepth
    scenePass.depthAttachment.loadAction = .clear
    scenePass.depthAttachment.storeAction = .dontCare
    scenePass.depthAttachment.clearDepth = 1.0

    let brightPass = makePostPass(bloomHalf)
    let blurHPass = makePostPass(bloomBlurA)
    let blurVPass = makePostPass(bloomBlurB)
    let compositePass = makePostPass(targetTexture ?? final)

    let viewProjection = makeViewProjection()
    var light = SIMD3<Float>(0.45, 0.85, 0.3)
    let halfWidth = Float(width / 2)
    let halfHeight = Float(height / 2)
    var time = Float(frameIndex % 4096) * 0.008

    // 1) Céu + cena 3D (HDR, MSAA 4x)
    guard let sceneEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass)
    else {
      return false
    }

    if let skyDepthState = skyDepthState {
      sceneEncoder.setDepthStencilState(skyDepthState)
    }
    sceneEncoder.setRenderPipelineState(background)
    sceneEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
    var skyIterations = backgroundIterations
    sceneEncoder.setFragmentBytes(
      &skyIterations,
      length: MemoryLayout<UInt32>.size,
      index: 1
    )
    sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

    if let sceneDepthState = sceneDepthState {
      sceneEncoder.setDepthStencilState(sceneDepthState)
    }
    sceneEncoder.setRenderPipelineState(scene)
    var matrix = viewProjection
    sceneEncoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.stride, index: 0)
    sceneEncoder.setVertexBytes(&time, length: MemoryLayout<Float>.size, index: 1)
    sceneEncoder.setVertexBuffer(mesh, offset: 0, index: 2)
    sceneEncoder.setFragmentBytes(&light, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
    sceneEncoder.drawPrimitives(
      type: .triangle,
      vertexStart: 0,
      vertexCount: 36,
      instanceCount: sceneInstances
    )
    sceneEncoder.endEncoding()

    // 2) Bright pass (bloom: extrai altas luzes)
    guard let brightEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: brightPass)
    else {
      return false
    }
    brightEncoder.setRenderPipelineState(bright)
    brightEncoder.setFragmentTexture(hdr, index: 0)
    brightEncoder.setFragmentSamplerState(sampler, index: 0)
    brightEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    brightEncoder.endEncoding()

    // 3) Blur horizontal
    guard let blurH = commandBuffer.makeRenderCommandEncoder(descriptor: blurHPass) else {
      return false
    }
    blurH.setRenderPipelineState(blur)
    blurH.setFragmentTexture(bloomHalf, index: 0)
    blurH.setFragmentSamplerState(sampler, index: 0)
    var dirH = SIMD2<Float>(1.25 / halfWidth, 0)
    blurH.setFragmentBytes(&dirH, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    blurH.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    blurH.endEncoding()

    // 4) Blur vertical
    guard let blurV = commandBuffer.makeRenderCommandEncoder(descriptor: blurVPass) else {
      return false
    }
    blurV.setRenderPipelineState(blur)
    blurV.setFragmentTexture(bloomBlurA, index: 0)
    blurV.setFragmentSamplerState(sampler, index: 0)
    var dirV = SIMD2<Float>(0, 1.25 / halfHeight)
    blurV.setFragmentBytes(&dirV, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    blurV.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    blurV.endEncoding()

    // 5) Composite (ACES tonemap + bloom)
    guard let compositor = commandBuffer.makeRenderCommandEncoder(descriptor: compositePass)
    else {
      return false
    }
    compositor.setRenderPipelineState(composite)
    compositor.setFragmentTexture(hdr, index: 0)
    compositor.setFragmentTexture(bloomBlurB, index: 1)
    compositor.setFragmentSamplerState(sampler, index: 0)
    compositor.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    compositor.endEncoding()

    return true
  }

  private func makePostPass(_ texture: MTLTexture) -> MTLRenderPassDescriptor {
    let descriptor = MTLRenderPassDescriptor()
    descriptor.colorAttachments[0].texture = texture
    descriptor.colorAttachments[0].loadAction = .dontCare
    descriptor.colorAttachments[0].storeAction = .store
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
    return descriptor
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
