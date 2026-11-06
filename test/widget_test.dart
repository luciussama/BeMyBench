import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bemybench/main.dart';

void main() {
  testWidgets('BMyBench app builds and shows tabs', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const BMyBenchApp());
      // Deixa os Process.run (sysctl/ioreg) terminarem de verdade
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    expect(find.textContaining('BMyBench'), findsWidgets);
    expect(find.text('Hardware'), findsWidgets);
    expect(find.text('Sensores'), findsWidgets);
    expect(find.text('Bateria'), findsWidgets);
    expect(find.text('Benchmark'), findsWidgets);
    expect(find.text('Estresse'), findsWidgets);
    expect(find.text('Histórico'), findsWidgets);

    // Substitui a árvore e avança o AnimatedSwitcher para acionar dispose() e cancelar o timer
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
