import 'dart:io';

import 'package:flutter/services.dart';

class BatteryInfo {
  final int percentage;
  final int cycleCount;
  final int designCapacity;
  final int maxCapacity;
  final int currentCapacity;
  final int voltage;
  final bool isCharging;
  final bool externalConnected;
  final double? temperatureC;
  final String? healthStatus;

  BatteryInfo({
    required this.percentage,
    required this.cycleCount,
    required this.designCapacity,
    required this.maxCapacity,
    required this.currentCapacity,
    required this.voltage,
    required this.isCharging,
    required this.externalConnected,
    this.temperatureC,
    this.healthStatus,
  });

  double get health {
    if (designCapacity <= 0) return 100.0;
    return ((maxCapacity / designCapacity) * 100).clamp(0.0, 100.0);
  }

  Map<String, String> toDisplayMap() {
    return {
      'Nível': '$percentage%',
      'Saúde': healthStatus ?? '${health.toStringAsFixed(1)}%',
      'Ciclos': cycleCount > 0 ? '$cycleCount' : 'N/D no kernel',
      'Capacidade Design': '$designCapacity mAh',
      'Capacidade Atual (Máx)': '$maxCapacity mAh',
      'Carga Atual': '$currentCapacity mAh',
      'Tensão': '${(voltage / 1000).toStringAsFixed(2)} V',
      if (temperatureC != null) 'Temperatura': '${temperatureC!.toStringAsFixed(1)} °C',
      'Status': isCharging ? 'Carregando' : (externalConnected ? 'Conectado (AC/USB)' : 'Descarregando'),
    };
  }
}

class BatteryService {
  static const _channel = MethodChannel('bemybench/battery');

  Future<BatteryInfo?> collect() async {
    if (Platform.isMacOS) {
      return await _collectMac();
    }
    if (Platform.isAndroid) {
      return await _collectAndroid();
    }
    return null;
  }

  Future<BatteryInfo?> _collectAndroid() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('get_battery');
      if (res != null) {
        final percent = res['percentage'] as int? ?? 0;
        final cycles = res['cycleCount'] as int? ?? 0;
        final design = res['designCapacity'] as int? ?? 5000;
        final maxCap = res['maxCapacity'] as int? ?? 5000;
        final currentCap = res['currentCapacity'] as int? ?? ((design * percent) ~/ 100);
        final voltage = res['voltage'] as int? ?? 3850;
        final isCharging = res['isCharging'] as bool? ?? false;
        final external = res['externalConnected'] as bool? ?? false;
        final tempC = (res['temperatureC'] as num?)?.toDouble();
        final healthStatus = res['healthStatus'] as String?;

        return BatteryInfo(
          percentage: percent,
          cycleCount: cycles,
          designCapacity: design,
          maxCapacity: maxCap,
          currentCapacity: currentCap,
          voltage: voltage,
          isCharging: isCharging,
          externalConnected: external,
          temperatureC: tempC,
          healthStatus: healthStatus,
        );
      }
    } catch (_) {}

    // Fallback via sysfs no Linux/Android se o canal não estiver pronto
    try {
      int readInt(String path) {
        final f = File(path);
        if (f.existsSync()) {
          return int.tryParse(f.readAsStringSync().trim()) ?? 0;
        }
        return 0;
      }

      String readStr(String path) {
        final f = File(path);
        if (f.existsSync()) {
          return f.readAsStringSync().trim();
        }
        return '';
      }

      const basePath = '/sys/class/power_supply/battery';
      if (Directory(basePath).existsSync()) {
        final capacity = readInt('$basePath/capacity');
        final status = readStr('$basePath/status');
        final voltageUv = readInt('$basePath/voltage_now');
        final voltageMv = voltageUv > 100000 ? voltageUv ~/ 1000 : voltageUv;
        final isCharging = status.toLowerCase().contains('charging');

        return BatteryInfo(
          percentage: capacity,
          cycleCount: readInt('$basePath/cycle_count'),
          designCapacity: 5000,
          maxCapacity: 5000,
          currentCapacity: (5000 * capacity) ~/ 100,
          voltage: voltageMv > 0 ? voltageMv : 3850,
          isCharging: isCharging,
          externalConnected: isCharging,
          healthStatus: 'Boa (sysfs)',
        );
      }
    } catch (_) {}

    return null;
  }

  Future<BatteryInfo?> _collectMac() async {
    try {
      final res = await Process.run('ioreg', ['-rn', 'AppleSmartBattery']);
      final out = res.stdout as String;

      int getValue(String key) {
        final reg = RegExp('"$key"\\s*=\\s*(\\d+)');
        final match = reg.firstMatch(out);
        return int.tryParse(match?.group(1) ?? '0') ?? 0;
      }

      bool getBool(String key) {
        final reg = RegExp('"$key"\\s*=\\s*(\\w+)');
        final match = reg.firstMatch(out);
        return match?.group(1)?.toLowerCase() == 'yes';
      }

      final current = getValue('AppleRawCurrentCapacity');
      final max = getValue('AppleRawMaxCapacity');
      final design = getValue('DesignCapacity');
      final cycles = getValue('CycleCount');
      final voltage = getValue('Voltage');
      final isCharging = getBool('IsCharging');
      final external = getBool('ExternalConnected');
      final percent = getValue('CurrentCapacity');

      return BatteryInfo(
        percentage: percent,
        cycleCount: cycles,
        designCapacity: design,
        maxCapacity: max,
        currentCapacity: current,
        voltage: voltage,
        isCharging: isCharging,
        externalConnected: external,
      );
    } catch (_) {
      return null;
    }
  }
}
