// ignore_for_file: avoid_print
// Script de verificação manual dos sensores (não faz parte do app).
//
//   ../../flutter/bin/dart run tool/check_sensors.dart

import 'package:bemybench/features/sensors/sensors_service.dart';

Future<void> main() async {
  final service = SensorsService();
  print('--- BMyBench :: Sensors Probe ---');
  for (var i = 1; i <= 3; i++) {
    final s = await service.collect();
    print(
      'amostra $i -> CPU ${s.cpuUsagePercent.toStringAsFixed(1)}% | '
      'RAM ${s.ramUsedLabel}/${s.ramTotalLabel} '
      '(${s.ramUsagePercent.toStringAsFixed(1)}%)',
    );
  }
}
