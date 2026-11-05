import 'package:bemybench/features/benchmark/gpu_benchmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('canal Metal responde info e run', (tester) async {
    final service = GpuBenchmarkService();

    final info = await service.info();
    expect(info, isNotNull);
    expect(info!.name, isNotEmpty);
    expect(info.width, 1920);
    expect(info.height, 1080);

    final result = await service.run(durationMs: 800);
    expect(result.fps, greaterThan(0));
    expect(result.score, greaterThan(0));
    expect(result.frames, greaterThan(0));
    expect(result.device, isNotEmpty);

    // ignore: avoid_print
    print(
      'GPU OK: ${result.device} · ${result.fps} fps · '
      'score ${result.score} · ${result.frames} frames',
    );
  });
}
