import 'package:flutter_test/flutter_test.dart';

import 'package:bemybench/main.dart';

void main() {
  testWidgets('BMyBench app builds and shows tabs', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const BMyBenchApp());
      // Deixa os Process.run (sysctl/ioreg) terminarem de verdade
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();

    expect(find.textContaining('BMyBench'), findsWidgets);
    expect(find.text('Sistema'), findsWidgets);
    expect(find.text('Sensores'), findsWidgets);
    expect(find.text('Bateria'), findsWidgets);
    expect(find.text('Benchmark'), findsWidgets);
  });
}
