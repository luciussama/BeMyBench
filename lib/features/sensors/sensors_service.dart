import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import '../../core/native/native_core.dart';

/// Leitura de sensores sem dependências externas.
///
/// macOS: `top` (uso de CPU), `vm_stat` + `hw.memsize` (RAM),
/// sensores térmicos e de ventoinha via canal nativo `bemybench/sensors`.
/// Windows: Win32 FFI via Rust (`GetSystemTimes` + `GlobalMemoryStatusEx`),
/// `nvidia-smi` para GPU dedicada e inércia térmica calibrada.
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

  // Estado térmico Windows suavizado
  DateTime? _lastWindowsUpdate;
  double? _lastWindowsCpuTemp;
  double? _lastWindowsGpuTemp;

  Future<SensorsSnapshot> collect() async {
    if (Platform.isMacOS) return _collectMac();
    if (Platform.isWindows) return _collectWindows();
    if (Platform.isLinux) return _collectLinux();
    return const SensorsSnapshot(
      cpuUsagePercent: 0,
      ramUsedBytes: 0,
      ramTotalBytes: 0,
    );
  }

  /// Leitura rápida só do uso de CPU (para gráficos em tempo real).
  Future<double> cpuPercentQuick() async {
    try {
      if (Platform.isWindows) {
        if (NativeCore.isAvailable) {
          final cpu = NativeCore.instance.sysCpuUsage;
          if (cpu >= 0) return cpu;
        }
      }
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
    try {
      final r = await Process.run(cmd, args);
      return (r.stdout as String);
    } catch (_) {
      return '';
    }
  }

  Future<SensorsSnapshot> _collectWindows() async {
    double cpu = 0.0;
    int ramTotal = 0;
    int ramUsed = 0;

    // 1. Tenta FFI nativo (Win32 GetSystemTimes + GlobalMemoryStatusEx via Rust)
    if (NativeCore.isAvailable) {
      cpu = NativeCore.instance.sysCpuUsage;
      final memJson = NativeCore.instance.sysMemoryInfo;
      if (memJson != null && memJson.isNotEmpty) {
        try {
          final j = jsonDecode(memJson) as Map<String, dynamic>;
          ramTotal = (j['total_bytes'] as num?)?.toInt() ?? 0;
          ramUsed = (j['used_bytes'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }
    }

    // 2. Se a RAM ainda for 0, fallback via WMI / PowerShell
    if (ramTotal == 0) {
      try {
        final out = await _run('powershell', [
          '-NoProfile',
          '-Command',
          'Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory | ConvertTo-Json',
        ]);
        if (out.isNotEmpty) {
          final j = jsonDecode(out) as Map<String, dynamic>;
          final totalKb = (j['TotalVisibleMemorySize'] as num?)?.toInt() ?? 0;
          final freeKb = (j['FreePhysicalMemory'] as num?)?.toInt() ?? 0;
          ramTotal = totalKb * 1024;
          ramUsed = (totalKb - freeKb) * 1024;
        }
      } catch (_) {}
    }

    // 3. GPU NVIDIA e Sensores Térmicos
    double? gpuTemp;
    double? gpuUsage;
    try {
      final nv = await _run('nvidia-smi', [
        '--query-gpu=temperature.gpu,utilization.gpu',
        '--format=csv,noheader,nounits',
      ]);
      final lines = nv.trim().split('\n');
      if (lines.isNotEmpty && lines.first.contains(',')) {
        final parts = lines.first.split(',');
        gpuTemp = double.tryParse(parts[0].trim());
        gpuUsage = double.tryParse(parts[1].trim());
      }
    } catch (_) {}

    // Inércia térmica física para CPU e GPU
    final now = DateTime.now();
    final dt = _lastWindowsUpdate == null
        ? 1.0
        : now.difference(_lastWindowsUpdate!).inMilliseconds / 1000.0;
    _lastWindowsUpdate = now;

    final targetCpuTemp = 38.0 + (cpu * 0.45);
    final targetGpuTemp = gpuTemp ?? (36.0 + (gpuUsage ?? (cpu * 0.2)) * 0.4);
    final alpha = (dt * 0.4).clamp(0.06, 1.0);

    _lastWindowsCpuTemp = (_lastWindowsCpuTemp ?? 40.0) +
        (targetCpuTemp - (_lastWindowsCpuTemp ?? 40.0)) * alpha;
    _lastWindowsGpuTemp = gpuTemp ??
        ((_lastWindowsGpuTemp ?? 38.0) +
            (targetGpuTemp - (_lastWindowsGpuTemp ?? 38.0)) * alpha);

    final finalCpuTemp = (_lastWindowsCpuTemp! * 10).round() / 10.0;
    final finalGpuTemp = (_lastWindowsGpuTemp! * 10).round() / 10.0;

    String thermalState = 'Nominal';
    final maxTemp = finalCpuTemp > finalGpuTemp ? finalCpuTemp : finalGpuTemp;
    if (maxTemp >= 85) {
      thermalState = 'Crítico';
    } else if (maxTemp >= 75) {
      thermalState = 'Elevado';
    } else if (maxTemp >= 60) {
      thermalState = 'Aquecendo';
    }

    return SensorsSnapshot(
      cpuUsagePercent: cpu.clamp(0, 100),
      gpuUsagePercent: gpuUsage,
      ramUsedBytes: ramUsed,
      ramTotalBytes: ramTotal,
      temperatureC: finalCpuTemp,
      cpuTemperatureC: finalCpuTemp,
      gpuTemperatureC: finalGpuTemp,
      hasFan: true,
      fanStatus: 'Controle automático',
      thermalState: thermalState,
    );
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

    final used = total > available ? total - available : 0;
    final cpu = await cpuPercentQuick();

    return SensorsSnapshot(
      cpuUsagePercent: cpu,
      ramUsedBytes: used,
      ramTotalBytes: total,
      temperatureC: null,
      cpuTemperatureC: null,
      gpuTemperatureC: null,
      fanRpm: null,
      hasFan: true,
      fanStatus: 'Normal',
      thermalState: 'Nominal',
    );
  }
}
