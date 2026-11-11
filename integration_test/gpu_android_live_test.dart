import 'package:bemybench/features/benchmark/gpu_benchmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Valida a visualização 3D ao vivo do Android (overlay em tela cheia com
/// GLSurfaceView + HUD) e a amostragem do benchmark a partir dela.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('visualização 3D abre, mede e fecha no Android', (tester) async {
    final service = GpuBenchmarkService();
    expect(GpuBenchmarkService.isSupported, isTrue);
    expect(GpuBenchmarkService.backendLabel, 'OpenGL ES');

    final info = await service.info();
    expect(info, isNotNull);
    expect(info!.name, isNotEmpty);
    expect(info.renderAvailable, isTrue);
    // ignore: avoid_print
    print('GPU Android: ${info.name} · ${info.api}');

    expect(await service.is3dWindowOpen(), isFalse);

    final opened = await service.open3dWindow(mode: 'stress');
    expect(opened, isTrue);
    expect(await service.is3dWindowOpen(), isTrue);

    // Com a visualização aberta, o resultado vem do throughput da cena ao vivo.
    final live = await service.runRender(durationMs: 800);
    expect(live.kind, 'render');
    expect(live.fps, greaterThan(0));
    expect(live.passes, 5);
    expect(live.bloom, isTrue);
    expect(live.instances, 1);
    expect(live.sceneLabel, contains('raymarch'));
    expect(live.pipelineLabel, 'bloom · 5 passes');
    // ignore: avoid_print
    print(
      'Render ao vivo OK: ${live.device} · ${live.fps} fps · '
      '1% low ${live.onePercentLowFps} fps · p99 ${live.p99FrameMs} ms · '
      'score ${live.score} · ${live.frames} quadros',
    );

    expect(await service.close3dWindow(), isTrue);
    expect(await service.is3dWindowOpen(), isFalse);

    // Sem a visualização, o benchmark roda off-screen no contexto EGL.
    final offscreen = await service.runRender(durationMs: 800);
    expect(offscreen.kind, 'render');
    expect(offscreen.fps, greaterThan(0));
    expect(offscreen.hasFrameStats, isTrue);
    // ignore: avoid_print
    print(
      'Render off-screen OK: ${offscreen.fps} fps · '
      'score ${offscreen.score} · ${offscreen.frames} quadros',
    );
  });
}
