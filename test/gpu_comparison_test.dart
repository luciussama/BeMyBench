import 'package:bemybench/features/benchmark/gpu_benchmark.dart';
import 'package:bemybench/features/benchmark/gpu_comparison_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('painel de GPU carrega a base e mostra compute + render',
      (tester) async {
    const compute = GpuBenchResult(
      kind: 'compute',
      device: 'Apple M5',
      width: 1920,
      height: 1080,
      iterations: 48,
      frames: 312,
      elapsedMs: 1184,
      fps: 262.8,
      pixelsPerSecond: 544856559,
      score: 26275.9,
    );
    const render = GpuBenchResult(
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
      avgFrameMs: 3.31,
      p99FrameMs: 3.6,
      p999FrameMs: 3.8,
      onePercentLowFps: 277.0,
      pointOnePercentLowFps: 262.0,
      frameTimeSamples: 340,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: GpuComparisonPanel(compute: compute, render: render),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Comparação de GPU com equipamentos similares'),
      findsOneWidget,
    );
    expect(find.textContaining('Seu dispositivo'), findsOneWidget);
    expect(find.textContaining('GPU raster (ref.)'), findsWidgets);
    expect(find.textContaining('Compute (ref.)'), findsWidgets);
    expect(find.textContaining('GPU render (jogos)'), findsOneWidget);
    expect(find.textContaining('Compute (BMyBench)'), findsOneWidget);
    expect(find.textContaining('1% low'), findsOneWidget);
    expect(find.textContaining('Equivalente mais próximo'), findsOneWidget);
  });
}
