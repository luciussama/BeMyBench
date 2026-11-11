import 'package:bemybench/features/benchmark/gpu_benchmark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpuBenchResult.fromMap', () {
    test('interpreta o resultado do backend OpenGL ES do Android', () {
      final result = GpuBenchResult.fromMap(<String, dynamic>{
        'available': true,
        'kind': 'render',
        'device': 'Adreno (TM) 750',
        'width': 1920,
        'height': 1080,
        'iterations': 32,
        'frames': 41,
        'elapsed_ms': 1523,
        'fps': 26.92,
        'pixels_per_second': 558504960.0,
        'score': 2692.0,
        'instances': 1,
        'triangles_per_frame': 2,
        'shading_iterations': 32,
        'msaa_samples': 0,
        'hdr': false,
        'bloom': true,
        'passes': 5,
        'avg_frame_ms': 37.14,
        'p99_frame_ms': 41.2,
        'p999_frame_ms': 47.38,
        'one_percent_low_fps': 24.27,
        'point_one_percent_low_fps': 21.84,
        'frame_time_samples': 41,
      });

      expect(result.isRender, isTrue);
      expect(result.device, 'Adreno (TM) 750');
      expect(result.shadingIterations, 32);
      expect(result.hasFrameStats, isTrue);
      expect(result.onePercentLowFps, closeTo(24.27, 0.001));

      // Sem MSAA nem HDR no OpenGL ES 2.0: o rótulo reflete só o que roda.
      expect(result.pipelineLabel, 'bloom · 5 passes');
      expect(
        result.sceneLabel,
        'raymarch volumétrico · 32 passos · 2 triângulos',
      );
    });

    test('interpreta o pipeline completo de cubos instanciados', () {
      const result = GpuBenchResult(
        kind: 'render',
        device: 'Apple M5',
        width: 1920,
        height: 1080,
        iterations: 24,
        frames: 340,
        elapsedMs: 1128,
        fps: 302.1,
        pixelsPerSecond: 626600000,
        score: 30210,
        instances: 1024,
        trianglesPerFrame: 12289,
        msaaSamples: 4,
        hdr: true,
        bloom: true,
        passes: 5,
        frameTimeSamples: 340,
      );

      expect(result.pipelineLabel, 'MSAA 4x · HDR · bloom · 5 passes');
      expect(result.sceneLabel, '1024 cubos · 12289 triângulos');
    });

    test('tolera mapas parciais sem quebrar a UI', () {
      final result = GpuBenchResult.fromMap(<String, dynamic>{
        'fps': 12.5,
      });

      expect(result.kind, 'compute');
      expect(result.fps, 12.5);
      expect(result.pipelineLabel, isEmpty);
      expect(result.sceneLabel, 'raymarch volumétrico · 0 triângulos');
    });
  });

  group('GpuInfo.fromMap', () {
    test('lê nome, memória unificada e API gráfica', () {
      final info = GpuInfo.fromMap(<String, dynamic>{
        'available': true,
        'render_available': true,
        'name': 'Mali-G715',
        'vendor': 'ARM',
        'api': 'OpenGL ES 3.2',
        'unified_memory': true,
        'recommended_working_set_mb': 256,
        'max_threads_per_group': 0,
        'width': 1920,
        'height': 1080,
      });

      expect(info.name, 'Mali-G715');
      expect(info.unifiedMemory, isTrue);
      expect(info.api, 'OpenGL ES 3.2');
      expect(info.renderAvailable, isTrue);
      expect(info.width, 1920);
    });
  });
}
