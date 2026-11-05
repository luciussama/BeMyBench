import 'dart:io';

import 'package:bemybench/features/history/bench_record.dart';
import 'package:bemybench/features/history/history_screen.dart';
import 'package:bemybench/features/history/history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late BenchHistoryStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bmybench_history_test_');
    store = BenchHistoryStore(directory: tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load retorna vazio com histórico inexistente', () async {
    expect(await store.load(), isEmpty);
  });

  test('append salva e load devolve registros ordenados', () async {
    await store.append(
      BenchRecord(
        timestamp: DateTime(2026, 11, 5, 10),
        cpuScore: 4800,
        memScore: 900,
        diskScore: 610,
        totalScore: 6310,
        osLabel: 'macOS',
      ),
    );
    await store.append(
      BenchRecord(
        timestamp: DateTime(2026, 11, 5, 11),
        cpuScore: 5000,
        memScore: 1000,
        diskScore: 620,
        gpuRenderScore: 280,
        totalScore: 6900,
        osLabel: 'macOS',
      ),
    );

    final records = await store.load();
    expect(records, hasLength(2));
    expect(records.first.cpuScore, 4800);
    expect(records.last.totalScore, 6900);
    expect(records.last.gpuRenderScore, 280);
  });

  test('load tolera arquivo corrompido', () async {
    final file = File('${tempDir.path}/history.json');
    await file.writeAsString('{ isto não é json válido !!!');

    expect(await store.load(), isEmpty);
  });

  test('clear apaga o histórico', () async {
    await store.append(
      BenchRecord(timestamp: DateTime(2026, 11, 5, 10), totalScore: 1000),
    );
    await store.clear();
    expect(await store.load(), isEmpty);
    expect(File('${tempDir.path}/history.json').existsSync(), isFalse);
  });

  Future<void> pumpHistory(WidgetTester tester, BenchHistoryStore store) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HistoryScreen(store: store))),
      );
      // Deixa o carregamento assíncrono do histórico terminar de verdade
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
  }

  testWidgets('tela vazia mostra orientação', (tester) async {
    await pumpHistory(tester, store);

    expect(find.text('Histórico de benchmarks'), findsOneWidget);
    expect(find.textContaining('Nenhuma execução salva'), findsOneWidget);
  });

  testWidgets('tela com registros mostra cards e totais', (tester) async {
    // testWidgets usa fake async; IO real só roda dentro de runAsync
    await tester.runAsync(() async {
      await store.append(
        BenchRecord(
          timestamp: DateTime(2026, 11, 4, 9),
          cpuScore: 4000,
          totalScore: 5000,
          osLabel: 'macOS',
        ),
      );
      await store.append(
        BenchRecord(
          timestamp: DateTime(2026, 11, 5, 9),
          cpuScore: 4500,
          totalScore: 6000,
          gpuRenderScore: 300,
          osLabel: 'macOS',
        ),
      );
    });

    await pumpHistory(tester, store);

    expect(find.text('Histórico de benchmarks'), findsOneWidget);
    expect(find.textContaining('Melhor total'), findsOneWidget);
    expect(find.textContaining('6000'), findsWidgets);
    expect(
      find.textContaining('Score total ao longo do tempo'),
      findsOneWidget,
    );
  });
}
