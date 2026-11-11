@Tags(['probe'])
library;

import 'dart:io';

import 'package:bemybench/features/sensors/sensors_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sonda manual: imprime as leituras granulares reais da máquina.
///
/// Roda como um teste comum (precisa do motor Flutter por causa do canal
/// nativo):
///
///   flutter test test/sensors_probe_test.dart --reporter expanded
///
/// Não substitui os testes de unidade — serve para conferir no hardware se
/// temperaturas de CPU/GPU e a carga por núcleo estão realmente disponíveis.
void main() {
  test('imprime as leituras reais de CPU, GPU e núcleos', () async {
    final service = SensorsService();

    // Duas amostras: a primeira só estabelece a base das taxas por núcleo.
    await service.collect();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final s = await service.collect();

    final cores = s.perCoreUsage
        .asMap()
        .entries
        .map((e) => 'N${e.key}=${e.value.toStringAsFixed(0)}%')
        .join(' ');

    // ignore: avoid_print
    print(
      'PROBE CPU=${s.cpuUsagePercent.toStringAsFixed(1)}% '
      'RAM=${s.ramUsagePercent.toStringAsFixed(0)}% '
      'TEMP_CPU=${_temp(s.cpuTemperatureC)} [${TempSource.label(s.cpuTempSource)}] '
      'TEMP_GPU=${_temp(s.gpuTemperatureC)} [${TempSource.label(s.gpuTempSource)}] '
      'THERMAL=${s.thermalState}',
    );
    // ignore: avoid_print
    print(
      cores.isEmpty
          ? 'PROBE CORES=indisponível'
          : 'PROBE CORES=${s.coreCount} média='
              '${s.perCoreAverage.toStringAsFixed(1)}% pico=N${s.perCorePeakIndex} '
              '${s.perCorePeak.toStringAsFixed(0)}% :: $cores',
    );

    // Sanidade mínima do que a plataforma expõe.
    expect(s.cpuUsagePercent, inInclusiveRange(0, 100));
    if (s.hasPerCore) {
      expect(s.perCoreUsage.length, s.coreCount);
      expect(
        s.perCoreUsage.every((v) => v >= 0 && v <= 100),
        isTrue,
      );
      if (!Platform.isMacOS && !Platform.isWindows) {
        // Linux/Android leem /proc/stat: deve refletir os núcleos do SO.
        expect(s.coreCount, Platform.numberOfProcessors);
      }
    }
  });
}

String _temp(double? value) =>
    value == null ? 'N/A' : '${value.toStringAsFixed(1)}C';
