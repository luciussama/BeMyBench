// ignore_for_file: avoid_print
// Script de verificação manual (não faz parte do app).
// Roda a leitura real da bateria no macOS e imprime o resultado.
//
//   ../../flutter/bin/dart run tool/check_battery.dart

import 'package:bemybench/features/battery/battery_service.dart';

Future<void> main() async {
  final service = BatteryService();
  final info = await service.collect();

  if (info == null) {
    print('Nenhuma bateria detectada (ou plataforma não suportada).');
    return;
  }

  print('--- BMyBench :: Battery Probe ---');
  info.toDisplayMap().forEach((k, v) => print('$k: $v'));
}
