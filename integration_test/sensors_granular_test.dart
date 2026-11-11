import 'dart:io';

import 'package:bemybench/features/sensors/sensors_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Valida no dispositivo real que a leitura granular funciona: temperatura de
/// CPU e de GPU separadas (com origem) e carga individual por núcleo.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sensores granulares: CPU/GPU separadas e por núcleo',
      (tester) async {
    final service = SensorsService();

    // Duas amostras: a taxa por núcleo depende da diferença entre leituras.
    final first = await service.collect();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final s = await service.collect();

    // ignore: avoid_print
    print(
      'GRANULAR CPU=${s.cpuUsageAvailable ? '${s.cpuUsagePercent.toStringAsFixed(1)}%' : 'N/A'} '
      'TEMP_CPU=${_fmt(s.cpuTemperatureC)} [${TempSource.label(s.cpuTempSource)}] '
      'TEMP_GPU=${_fmt(s.gpuTemperatureC)} [${TempSource.label(s.gpuTempSource)}] '
      'THERMAL=${s.thermalState}'
      '${s.thermalHeadroom != null ? ' HEADROOM=${s.thermalHeadroom!.toStringAsFixed(2)}' : ''}',
    );
    // ignore: avoid_print
    print(
      s.hasPerCoreLoad
          ? 'GRANULAR CORES=load ${s.coreCount} '
              'média=${s.perCoreAverage.toStringAsFixed(1)}% '
              'pico=N${s.perCorePeakIndex} ${s.perCorePeak.toStringAsFixed(0)}% :: '
              '${s.perCoreUsage.asMap().entries.map((e) => 'N${e.key}=${e.value.toStringAsFixed(0)}%').join(' ')}'
          : (s.hasPerCoreFrequency
              ? 'GRANULAR CORES=frequency ${s.coreCount} :: '
                  '${s.perCoreFrequencyMhz.asMap().entries.map((e) => 'N${e.key}=${e.value.toStringAsFixed(0)}MHz').join(' ')}'
              : 'GRANULAR CORES=indisponível'),
    );

    if (s.cpuUsageAvailable) {
      expect(s.cpuUsagePercent, inInclusiveRange(0, 100));
    }
    expect(s.ramTotalBytes, greaterThan(0));

    // Temperaturas separadas: cada uma tem sua própria origem. GPU pode não
    // existir no Android (o SO bloqueia zonas térmicas); CPU sempre tem algo.
    expect(s.cpuTemperatureC, isNotNull, reason: 'CPU sem temperatura');
    expect(s.cpuTemperatureC!, inInclusiveRange(0, 150));
    expect(s.cpuTempSource, isNotEmpty);
    if (s.gpuTemperatureC != null) {
      expect(s.gpuTemperatureC!, inInclusiveRange(0, 150));
      expect(s.gpuTempSource, isNotEmpty);
    }
    if (Platform.isWindows || Platform.isMacOS) {
      // Desktop tem sensor (ou modelo térmico) para as duas.
      expect(s.gpuTemperatureC, isNotNull, reason: 'GPU sem temperatura');
    }

    // Por núcleo: carga real ou frequência (fallback do Android).
    expect(s.hasPerCore, isTrue, reason: 'sem leitura por núcleo');
    if (s.hasPerCoreLoad) {
      expect(s.coreCount, Platform.numberOfProcessors);
      expect(s.perCoreUsage.every((v) => v >= 0 && v <= 100), isTrue);
      expect(s.perCoreAverage, inInclusiveRange(0, 100));
    } else {
      expect(s.perCoreFrequencyMhz.every((v) => v > 0), isTrue);
      expect(s.perCoreFrequencyReference, greaterThan(0));
    }

    // A primeira amostra pode não ter taxa por núcleo (só a base), mas não
    // deve devolver valores inválidos.
    expect(first.perCoreUsage.every((v) => v >= 0 && v <= 100), isTrue);
  });
}

String _fmt(double? value) =>
    value == null ? 'N/A' : '${value.toStringAsFixed(1)}C';
