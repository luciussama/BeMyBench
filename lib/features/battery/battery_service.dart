import 'dart:io';

class BatteryInfo {
  final int percentage;
  final int cycleCount;
  final int designCapacity;
  final int maxCapacity;
  final int currentCapacity;
  final int voltage;
  final bool isCharging;
  final bool externalConnected;

  BatteryInfo({
    required this.percentage,
    required this.cycleCount,
    required this.designCapacity,
    required this.maxCapacity,
    required this.currentCapacity,
    required this.voltage,
    required this.isCharging,
    required this.externalConnected,
  });

  double get health => (maxCapacity / designCapacity) * 100;

  Map<String, String> toDisplayMap() {
    return {
      'Nível': '$percentage%',
      'Saúde': '${health.toStringAsFixed(1)}%',
      'Ciclos': '$cycleCount',
      'Capacidade Design': '$designCapacity mAh',
      'Capacidade Atual (Máx)': '$maxCapacity mAh',
      'Carga Atual': '$currentCapacity mAh',
      'Tensão': '${(voltage / 1000).toStringAsFixed(2)} V',
      'Status': isCharging ? 'Carregando' : (externalConnected ? 'Conectado (AC)' : 'Descarregando'),
    };
  }
}

class BatteryService {
  Future<BatteryInfo?> collect() async {
    if (Platform.isMacOS) {
      return await _collectMac();
    }
    // TODO: implementar Windows, Linux, Android
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

      // No Apple Silicon, os valores mAh ficam dentro de "BatteryData"
      // mas o ioreg joga tudo no mesmo output de texto, então o regex acima funciona.
      
      final current = getValue('AppleRawCurrentCapacity');
      final max = getValue('AppleRawMaxCapacity');
      final design = getValue('DesignCapacity');
      final cycles = getValue('CycleCount');
      final voltage = getValue('Voltage');
      final isCharging = getBool('IsCharging');
      final external = getBool('ExternalConnected');
      final percent = getValue('CurrentCapacity'); // Este costuma ser o % direto

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
    } catch (e) {
      return null;
    }
  }
}
