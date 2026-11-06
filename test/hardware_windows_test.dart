import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bemybench/features/hardware/hardware_service.dart';
import 'package:bemybench/features/storage/storage_service.dart';

void main() {
  test('HardwareService no Windows coleta métricas de hardware reais e granulares', () async {
    if (!Platform.isWindows) return;

    final service = HardwareService();
    final info = await service.collect();

    expect(info.osName, contains('Windows'));
    expect(info.cores, greaterThan(0));
    expect(info.ramTotalBytes, greaterThan(0));
    expect(info.chip, isNot('N/A'));
    expect(info.chip, isNot('Processador Windows'));
    expect(info.motherboard.modelName, isNot('Genérico'));
    expect(info.gpu.model, isNot('GPU Padrão'));
    expect(info.storageDisks.isNotEmpty, isTrue);

    final storageService = StorageService();
    final volumes = await storageService.collect();
    expect(volumes.isNotEmpty, isTrue);
    expect(volumes.any((v) => v.mount.contains('C:')), isTrue);
  });
}
