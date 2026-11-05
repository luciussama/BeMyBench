import 'package:bemybench/features/benchmark/gpu_benchmark.dart';
import 'package:bemybench/features/benchmark/gpu_comparison_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('painel de GPU carrega a base e mostra o usuário', (tester) async {
    const gpu = GpuBenchResult(
      device: 'Apple M5',
      width: 1920,
      height: 1080,
      iterations: 48,
      frames: 312,
      elapsedMs: 1184,
      fps: 263.47,
      pixelsPerSecond: 546333758,
      score: 26347.1,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: GpuComparisonPanel(gpu: gpu),
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
    expect(find.textContaining('Equivalente mais próximo'), findsOneWidget);
  });
}
