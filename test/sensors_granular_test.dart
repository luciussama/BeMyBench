import 'package:bemybench/features/sensors/cpu_cores_panel.dart';
import 'package:bemybench/features/sensors/sensors_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _procStatSample = '''
cpu  100 0 50 850 0 0 0 0 0 0
cpu0 10 0 5 85 0 0 0 0 0 0
cpu1 20 0 10 70 0 0 0 0 0 0
intr 12345 0 0
ctxt 999
''';

SensorsSnapshot _snapshotWith(List<double> cores) => SensorsSnapshot(
      cpuUsagePercent: 42,
      ramUsedBytes: 8 * 1024 * 1024 * 1024,
      ramTotalBytes: 16 * 1024 * 1024 * 1024,
      cpuTemperatureC: 58,
      gpuTemperatureC: 64,
      cpuTempSource: TempSource.acpi,
      gpuTempSource: TempSource.gpuDriver,
      perCoreUsage: cores,
      thermalState: 'Nominal',
    );

void main() {
  group('CpuTimes.parse (/proc/stat)', () {
    test('separa a linha agregada das linhas por núcleo', () {
      final times = CpuTimes.parse(_procStatSample);

      expect(times, isNotNull);
      expect(times!.aggregate!.total, 1000);
      expect(times.aggregate!.idle, 850);
      expect(times.perCore.length, 2);
      expect(times.perCore[0].total, 100);
      expect(times.perCore[0].idle, 85);
      expect(times.perCore[1].total, 100);
      expect(times.perCore[1].idle, 70);
    });

    test('ignora conteúdo inválido', () {
      expect(CpuTimes.parse(''), isNull);
      expect(CpuTimes.parse('intr 123 0 0'), isNull);
    });
  });

  group('CpuTicks.usageSince', () {
    test('calcula a taxa entre duas amostras', () {
      const previous = CpuTicks(1000, 850);
      const current = CpuTicks(1200, 900); // +200 total, +50 idle → 75% busy
      expect(current.usageSince(previous), closeTo(75, 0.01));
    });

    test('sem delta devolve a média desde o boot', () {
      const sample = CpuTicks(1000, 850);
      expect(sample.usageSince(sample), closeTo(15, 0.01));
    });

    test('é resiliente a contadores que voltam (overflow/reset)', () {
      const previous = CpuTicks(1000, 850);
      const current = CpuTicks(10, 5);
      expect(current.usageSince(previous), closeTo(50, 0.01));
    });
  });

  group('SensorsSnapshot granular', () {
    test('agrega núcleos (média, pico e índice do pico)', () {
      final snapshot = _snapshotWith(const [10, 80, 30, 40]);

      expect(snapshot.hasPerCore, isTrue);
      expect(snapshot.coreCount, 4);
      expect(snapshot.perCoreAverage, closeTo(40, 0.01));
      expect(snapshot.perCorePeak, 80);
      expect(snapshot.perCorePeakIndex, 1);
    });

    test('sem leitura por núcleo não quebra os agregados', () {
      final snapshot = _snapshotWith(const []);

      expect(snapshot.hasPerCore, isFalse);
      expect(snapshot.coreCount, 0);
      expect(snapshot.perCoreAverage, 0);
      expect(snapshot.perCorePeak, 0);
      expect(snapshot.perCorePeakIndex, 0);
    });

    test('temperaturas de CPU e GPU são independentes e rotuladas', () {
      final snapshot = _snapshotWith(const [1, 2]);

      expect(snapshot.cpuTemperatureC, 58);
      expect(snapshot.gpuTemperatureC, 64);
      expect(snapshot.cpuTempEstimated, isFalse);
      expect(snapshot.gpuTempEstimated, isFalse);
      expect(TempSource.label(TempSource.model), 'estimado');
      expect(TempSource.label(''), '');
      expect(TempSource.label(TempSource.acpi), 'ACPI');
    });
  });

  group('CpuCoresPanel', () {
    testWidgets('mostra um cartão por núcleo com o resumo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CpuCoresPanel(
                snapshot: _snapshotWith(const [12, 88, 40, 4]),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Utilização da CPU por núcleo'), findsOneWidget);
      expect(find.text('4 núcleos lógicos'), findsOneWidget);
      expect(find.text('N0'), findsOneWidget);
      expect(find.text('N3'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      // '88%' aparece no cartão do núcleo e no resumo de pico.
      expect(find.text('88%'), findsNWidgets(2));
      expect(find.text('Pico (N1)'), findsOneWidget);
      expect(find.text('Média'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
    });

    testWidgets('explica quando não há leitura por núcleo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CpuCoresPanel(snapshot: _snapshotWith(const [])),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('não está disponível nesta plataforma'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('usa frequência por núcleo quando a carga é bloqueada',
        (tester) async {
      const snapshot = SensorsSnapshot(
        cpuUsagePercent: 0,
        cpuUsageAvailable: false,
        ramUsedBytes: 4 * 1024 * 1024 * 1024,
        ramTotalBytes: 8 * 1024 * 1024 * 1024,
        cpuTemperatureC: 31,
        cpuTempSource: TempSource.battery,
        gpuTemperatureC: null,
        perCoreFrequencyMhz: [800, 2400, 2400, 1200],
        perCoreFrequencyMaxMhz: 2400,
        thermalHeadroom: 0.42,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: CpuCoresPanel(snapshot: snapshot),
            ),
          ),
        ),
      );

      expect(find.text('Frequência da CPU por núcleo'), findsOneWidget);
      expect(find.text('4 núcleos lógicos'), findsOneWidget);
      expect(find.text('800 MHz'), findsOneWidget);
      // Dois núcleos a 2400 MHz + resumo (Máxima e Referência).
      expect(find.text('2.40 GHz'), findsNWidgets(4));
      expect(find.text('Referência'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
      expect(snapshot.hasPerCoreLoad, isFalse);
      expect(snapshot.hasPerCoreFrequency, isTrue);
      expect(snapshot.cpuUsageAvailable, isFalse);
    });
  });
}
