import 'package:bemybench/features/benchmark/benchmark_models.dart';
import 'package:bemybench/features/benchmark/comparison_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('painel de comparação carrega a base e mostra o usuário',
      (tester) async {
    const cpu = CpuBenchResult(
      singleMops: 602.0,
      multiMops: 4270.1,
      threads: 10,
      durationMs: 1000,
      score: 4872.1,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: ComparisonPanel(cpu: cpu),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Comparação com equipamentos similares'), findsOneWidget);
    expect(find.textContaining('Seu dispositivo'), findsOneWidget);
    expect(find.textContaining('CPU multi (ref.)'), findsWidgets);
    expect(find.textContaining('Equivalente mais próximo'), findsOneWidget);
  });
}
