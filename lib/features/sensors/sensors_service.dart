import 'dart:io';
import 'package:flutter/services.dart';

/// Leitura de sensores sem dependências externas.
///
/// macOS: `top` (uso de CPU), `vm_stat` + `hw.memsize` (RAM),
/// sensores térmicos e de ventoinha via canal nativo `bemybench/sensors`.
class SensorsSnapshot {
  final double cpuUsagePercent;
  final double? gpuUsagePercent;
  final int ramUsedBytes;
  final int ramTotalBytes;
  final double? temperatureC;
  final double? cpuTemperatureC;
  final double? gpuTemperatureC;
  final int? fanRpm;
  final bool hasFan;
  final String fanStatus;
  final String thermalState;

  const SensorsSnapshot({
    required this.cpuUsagePercent,
    this.gpuUsagePercent,
    required this.ramUsedBytes,
    required this.ramTotalBytes,
    this.temperatureC,
    this.cpuTemperatureC,
    this.gpuTemperatureC,
    this.fanRpm,
    this.hasFan = true,
    this.fanStatus = 'Normal',
    this.thermalState = 'Nominal',
  });

  double get ramUsagePercent =>
      ramTotalBytes == 0 ? 0 : (ramUsedBytes / ramTotalBytes) * 100;

  String get ramUsedLabel => _gb(ramUsedBytes);
  String get ramTotalLabel => _gb(ramTotalBytes);

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class SensorsService {
  static const _channel = MethodChannel('bemybench/sensors');
  int _pageSize = 4096;

  Future<SensorsSnapshot> collect() async {
    if (Platform.isMacOS) return _collectMac();
    if (Platform.isLinux) return _collectLinux();
    return const SensorsSnapshot(
      cpuUsagePercent: 0,
      ramUsedBytes: 0,
      ramTotalBytes: 0,
    );
  }

  /// Leitura rápida só do uso de CPU (para gráficos em tempo real).
  /// Evita o custo de `top -l 2` (~1s) usando `ps`.
  Future<double> cpuPercentQuick() async {
    try {
      if (Platform.isMacOS) {
        final out = await _run('ps', ['-A', '-o', '%cpu=']);
        final sum = out
            .split('\n')
            .map((l) => double.tryParse(l.trim()) ?? 0)
            .fold<double>(0, (a, b) => a + b);
        final cores = Platform.numberOfProcessors;
        return (sum / cores).clamp(0.0, 100.0);
      }
      if (Platform.isLinux) {
        final s = await _run('cat', ['/proc/stat']);
        final first = s.split('\n').first.split(RegExp(r'\s+'));
        final v = first.skip(1).take(7).map(int.parse).toList();
        final total = v.fold<int>(0, (a, b) => a + b);
        final idle = v[3] + (v.length > 4 ? v[4] : 0);
        if (total == 0) return 0;
        return ((total - idle) / total * 100).clamp(0.0, 100.0);
      }
    } catch (_) {}
    return 0;
  }

  Future<String> _run(String cmd, List<String> args) async {
    final r = await Process.run(cmd, args);
    return (r.stdout as String);
  }

  Future<SensorsSnapshot> _collectMac() async {
    // CPU: top com 2 amostras; a segunda linha "CPU usage" é a medição real.
    double cpu = 0;
    try {
      final top = await _run('top', ['-l', '2', '-n', '0', '-s', '1']);
      final matches = RegExp(r'CPU usage:\s*([\d.]+)% user,\s*([\d.]+)% sys')
          .allMatches(top)
          .toList();
      if (matches.isNotEmpty) {
        final m = matches.last;
        cpu = (double.tryParse(m.group(1)!) ?? 0) +
            (double.tryParse(m.group(2)!) ?? 0);
      }
    } catch (_) {}

    // RAM: vm_stat + hw.memsize
    int total = 0;
    int used = 0;
    try {
      final memsize = await _run('sysctl', ['-n', 'hw.memsize']);
      total = int.tryParse(memsize.trim()) ?? 0;

      final vm = await _run('vm_stat', []);
      final pageSizeMatch = RegExp(r'page size of (\d+) bytes').firstMatch(vm);
      _pageSize = int.tryParse(pageSizeMatch?.group(1) ?? '4096') ?? 4096;

      int pages(String label) {
        final m = RegExp('$label:\\s+(\\d+)').firstMatch(vm);
        return int.tryParse(m?.group(1) ?? '0') ?? 0;
      }

      final active = pages('Pages active');
      final wired = pages('Pages wired down');
      final compressed = pages('Pages occupied by compressor');
      used = (active + wired + compressed) * _pageSize;
    } catch (_) {}

    // Temperaturas, Ventoinha e Carga de GPU via canal nativo
    double? cpuTemp;
    double? gpuTemp;
    double? gpuUsage;
    double? tempC;
    bool hasFan = true;
    String fanStatus = 'Normal';
    String thermalState = 'Nominal';
    int? fanRpm;

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('get_sensors', {
        'cpu_usage': cpu,
      });
      if (res != null) {
        cpuTemp = (res['cpu_temp'] as num?)?.toDouble();
        gpuTemp = (res['gpu_temp'] as num?)?.toDouble();
        gpuUsage = (res['gpu_usage'] as num?)?.toDouble();
        tempC = cpuTemp ?? gpuTemp;
        hasFan = res['has_fan'] as bool? ?? true;
        fanStatus = res['fan_status'] as String? ?? 'Normal';
        thermalState = res['thermal_state'] as String? ?? 'Nominal';
        fanRpm = res['fan_rpm'] as int?;
      }
    } catch (_) {}

    return SensorsSnapshot(
      cpuUsagePercent: cpu.clamp(0, 100).toDouble(),
      gpuUsagePercent: gpuUsage,
      ramUsedBytes: used,
      ramTotalBytes: total,
      temperatureC: tempC,
      cpuTemperatureC: cpuTemp,
      gpuTemperatureC: gpuTemp,
      fanRpm: fanRpm,
      hasFan: hasFan,
      fanStatus: fanStatus,
      thermalState: thermalState,
    );
  }

  Future<SensorsSnapshot> _collectLinux() async {
    int total = 0, available = 0;
    try {
      final mem = await _run('cat', ['/proc/meminfo']);
      int kb(String key) {
        final m = RegExp('$key:\\s+(\\d+)').firstMatch(mem);
        return int.tryParse(m?.group(1) ?? '0') ?? 0;
      }

      total = kb('MemTotal') * 1024;
      available = kb('MemAvailable') * 1024;
    } catch (_) {}

    double cpu = 0;
    try {
      final s = await _run('cat', ['/proc/stat']);
      final first = s.split('\n').first.split(RegExp(r'\s+'));
      final v = first.skip(1).take(7).map(int.parse).toList();
      final total = v.fold<int>(0, (a, b) => a + b);
      final idle = v[3] + (v.length > 4 ? v[4] : 0);
      if (total > 0) cpu = ((total - idle) / total * 100).clamp(0.0, 100.0);
    } catch (_) {}

    return SensorsSnapshot(
      cpuUsagePercent: cpu.clamp(0, 100).toDouble(),
      ramUsedBytes: (total - available).clamp(0, total),
      ramTotalBytes: total,
    );
  }
}
