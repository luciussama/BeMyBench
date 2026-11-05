import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bemybench/features/stress/stress_screen.dart';

void main() {
  testWidgets('tela de estresse mostra CTA, opções e gráficos vazios', (
    tester,
  ) async {
    // Superfície alta para garantir que todos os painéis sejam construídos.
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StressScreen()),
      ),
    );

    expect(find.text('Estresse contínuo de GPU'), findsOneWidget);
    expect(find.text('INICIAR ESTRESSE'), findsOneWidget);
    expect(find.textContaining('30 segundos'), findsOneWidget);
    expect(find.textContaining('60 segundos'), findsOneWidget);
    expect(find.textContaining('Contínuo'), findsOneWidget);
    expect(find.textContaining('FPS ao longo do estresse'), findsOneWidget);
  });
}
