import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bemybench/features/sensors/sensors_service.dart';

void main() {
  test('SensorsService no Windows coleta métricas não-nulas e válidas', () async {
    if (!Platform.isWindows) return;

    final service = SensorsService();
    final snapshot = await service.collect();

    expect(snapshot.ramTotalBytes, greaterThan(0));
    expect(snapshot.ramUsedBytes, greaterThan(0));
    expect(snapshot.cpuUsagePercent, greaterThanOrEqualTo(0.0));
    expect(snapshot.cpuUsagePercent, lessThanOrEqualTo(100.0));
    expect(snapshot.temperatureC, isNotNull);
    expect(snapshot.temperatureC!, greaterThan(20.0));
    expect(snapshot.thermalState.isNotEmpty, isTrue);

    final quickCpu = await service.cpuPercentQuick();
    expect(quickCpu, greaterThanOrEqualTo(0.0));
  });
}
