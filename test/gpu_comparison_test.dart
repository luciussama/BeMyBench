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
      frames: 320,
      elapsedMs: 1182,
      fps: 270.8,
      pixelsPerSecond: 561600000,
      score: 27080,
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
    expect(find.textContaining('3DMark Time Spy'), findsWidgets);
    expect(find.textContaining('Geekbench 6 Metal'), findsWidgets);
    expect(find.textContaining('GPU render (jogos)'), findsOneWidget);
    expect(find.textContaining('GPU compute'), findsOneWidget);
    expect(find.textContaining('Equivalente mais próximo'), findsOneWidget);
  });
}
