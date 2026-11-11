import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/native/native_core.dart';

/// Origem de uma leitura de temperatura, exibida na UI para deixar claro o
/// que é sensor físico e o que é estimativa.
class TempSource {
  /// Sensor exposto pelo SO (hwmon/sysfs, zona térmica, ACPI, driver da GPU).
  static const sensor = 'sensor';

  /// Leitura do ACPI (zona térmica do firmware) no Windows.
  static const acpi = 'ACPI';

  /// Temperatura da GPU lida do driver (nvidia-smi).
  static const gpuDriver = 'nvidia-smi';

  /// Valor de um modelo térmico calibrado (sem acesso ao sensor).
  static const model = 'modelo';

  /// Bateria usada como proxy térmico no Android.
  static const battery = 'bateria';

  /// Rótulo amigável para exibição na UI.
  static String label(String source) {
    if (source.isEmpty) return '';
    if (source == model) return 'estimado';
    return source;
  }
}

/// Leitura de sensores sem dependências externas.
///
/// macOS: `top`/`vm_stat` em Dart, temperaturas e núcleos via canal nativo
/// `bemybench/sensors`; Windows: telemetria Win32 via Rust (uso de CPU,
/// núcleos individuais e zona térmica ACPI) + `nvidia-smi`; Linux: `/proc` e
/// `/sys`; Android: canal nativo (bateria, zonas térmicas, núcleos) com
/// fallback em `/proc`.
class SensorsSnapshot {
  final double cpuUsagePercent;
  final double? gpuUsagePercent;
  final int ramUsedBytes;
  final int ramTotalBytes;

  /// Maior temperatura conhecida (compatibilidade); a UI usa CPU e GPU.
  final double? temperatureC;
  final double? cpuTemperatureC;
  final double? gpuTemperatureC;

  /// Origem de cada temperatura (ver [TempSource]).
  final String cpuTempSource;
  final String gpuTempSource;

  /// Carga por núcleo lógico da CPU (0-100). Vazio quando indisponível.
  final List<double> perCoreUsage;

  /// Frequência atual por núcleo (MHz) quando o SO bloqueia a carga por núcleo
  /// (caso do Android 12+ com SELinux). É o fallback honesto: mede atividade
  /// real por núcleo, mas não é utilização.
  final List<double> perCoreFrequencyMhz;

  /// Frequência máxima de referência (MHz) para normalizar as barras.
  final double perCoreFrequencyMaxMhz;

  /// `false` quando o SO bloqueia a leitura do uso de CPU.
  final bool cpuUsageAvailable;

  /// Pressão térmica normalizada (1.0 ≈ limite de throttling), Android 10+.
  final double? thermalHeadroom;

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
    this.cpuTempSource = '',
    this.gpuTempSource = '',
    this.perCoreUsage = const [],
    this.perCoreFrequencyMhz = const [],
    this.perCoreFrequencyMaxMhz = 0,
    this.cpuUsageAvailable = true,
    this.thermalHeadroom,
    this.fanRpm,
    this.hasFan = true,
    this.fanStatus = 'Normal',
    this.thermalState = 'Nominal',
  });

  double get ramUsagePercent =>
      ramTotalBytes == 0 ? 0 : (ramUsedBytes / ramTotalBytes) * 100;

  String get ramUsedLabel => _gb(ramUsedBytes);
  String get ramTotalLabel => _gb(ramTotalBytes);

  /// Leitura de carga por núcleo disponível.
  bool get hasPerCoreLoad => perCoreUsage.isNotEmpty;

  /// Leitura por núcleo disponível apenas como frequência.
  bool get hasPerCoreFrequency =>
      !hasPerCoreLoad && perCoreFrequencyMhz.isNotEmpty;

  bool get hasPerCore => hasPerCoreLoad || hasPerCoreFrequency;

  int get coreCount =>
      hasPerCoreLoad ? perCoreUsage.length : perCoreFrequencyMhz.length;

  /// Frequência de referência (MHz) para normalizar as barras.
  double get perCoreFrequencyReference {
    if (perCoreFrequencyMaxMhz > 0) return perCoreFrequencyMaxMhz;
    if (perCoreFrequencyMhz.isEmpty) return 0;
    return perCoreFrequencyMhz.reduce((a, b) => a > b ? a : b);
  }

  double get perCoreAverage => perCoreUsage.isEmpty
      ? 0
      : perCoreUsage.reduce((a, b) => a + b) / perCoreUsage.length;

  double get perCorePeak =>
      perCoreUsage.isEmpty ? 0 : perCoreUsage.reduce((a, b) => a > b ? a : b);

  int get perCorePeakIndex {
    if (perCoreUsage.isEmpty) return 0;
    var index = 0;
    for (var i = 1; i < perCoreUsage.length; i++) {
      if (perCoreUsage[i] > perCoreUsage[index]) index = i;
    }
    return index;
  }

  bool get cpuTempEstimated => cpuTempSource == TempSource.model;
  bool get gpuTempEstimated => gpuTempSource == TempSource.model;

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

  // Amostra anterior de /proc/stat (Linux/Android) para calcular taxas.
  CpuTimes? _previousProcStat;

  // Amostra anterior para a leitura rápida (gráficos), independente do collect.
  CpuTicks? _previousQuickCpu;

  Future<SensorsSnapshot> collect() async {
    if (Platform.isMacOS) return _collectMac();
    if (Platform.isWindows) return _collectWindows();
    if (Platform.isAndroid) return _collectAndroid();
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
      if (Platform.isAndroid || Platform.isLinux) {
        final times = await _readProcStat();
        final aggregate = times?.aggregate;
        if (aggregate != null) {
          final previous = _previousQuickCpu;
          _previousQuickCpu = aggregate;
          if (previous != null) {
            return aggregate.usageSince(previous);
          }
          return aggregate.usageSince(aggregate);
        }
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

  /// Lê `/proc/stat` direto do sistema de arquivos (sem spawn de processo).
  Future<CpuTimes?> _readProcStat() async {
    try {
      final text = await File('/proc/stat').readAsString();
      return CpuTimes.parse(text);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- Windows ---

  Future<SensorsSnapshot> _collectWindows() async {
    double cpu = 0.0;
    int ramTotal = 0;
    int ramUsed = 0;
    var perCore = const <double>[];
    double? acpiCpuTemp;

    // 1. Telemetria Win32 via Rust (CPU, núcleos individuais, ACPI, RAM)
    if (NativeCore.isAvailable) {
      cpu = NativeCore.instance.sysCpuUsage;
      perCore = NativeCore.instance.sysCpuPerCore;
      acpiCpuTemp = NativeCore.instance.sysCpuTempC;
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

    // 3. GPU NVIDIA (temperatura real e uso) via driver
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

    // 4. Inércia térmica física apenas para o que não tem sensor disponível
    final now = DateTime.now();
    final dt = _lastWindowsUpdate == null
        ? 1.0
        : now.difference(_lastWindowsUpdate!).inMilliseconds / 1000.0;
    _lastWindowsUpdate = now;

    final modelCpuTemp = 38.0 + (cpu * 0.45);
    final modelGpuTemp = gpuTemp ?? (36.0 + (gpuUsage ?? (cpu * 0.2)) * 0.4);
    final alpha = (dt * 0.4).clamp(0.06, 1.0);

    _lastWindowsCpuTemp = (_lastWindowsCpuTemp ?? 40.0) +
        (modelCpuTemp - (_lastWindowsCpuTemp ?? 40.0)) * alpha;
    _lastWindowsGpuTemp = gpuTemp ??
        ((_lastWindowsGpuTemp ?? 38.0) +
            (modelGpuTemp - (_lastWindowsGpuTemp ?? 38.0)) * alpha);

    final finalCpuTemp = acpiCpuTemp ??
        (((_lastWindowsCpuTemp ?? 40.0) * 10).round() / 10.0);
    final finalGpuTemp = gpuTemp != null
        ? ((gpuTemp * 10).round() / 10.0)
        : ((_lastWindowsGpuTemp ?? 38.0) * 10).round() / 10.0;

    final cpuSource =
        acpiCpuTemp != null ? TempSource.acpi : TempSource.model;
    final gpuSource =
        gpuTemp != null ? TempSource.gpuDriver : TempSource.model;

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
      temperatureC: maxTemp,
      cpuTemperatureC: finalCpuTemp,
      gpuTemperatureC: finalGpuTemp,
      cpuTempSource: cpuSource,
      gpuTempSource: gpuSource,
      perCoreUsage: perCore,
      hasFan: true,
      fanStatus: 'Controle automático',
      thermalState: thermalState,
    );
  }

  // --------------------------------------------------------------- macOS ---

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
    bool hasFan = true;
    String fanStatus = 'Normal';
    String thermalState = 'Nominal';
    int? fanRpm;
    String cpuSource = '';
    String gpuSource = '';

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('get_sensors', {
        'cpu_usage': cpu,
      });
      if (res != null) {
        cpuTemp = (res['cpu_temp'] as num?)?.toDouble();
        gpuTemp = (res['gpu_temp'] as num?)?.toDouble();
        gpuUsage = (res['gpu_usage'] as num?)?.toDouble();
        hasFan = res['has_fan'] as bool? ?? true;
        fanStatus = res['fan_status'] as String? ?? 'Normal';
        thermalState = res['thermal_state'] as String? ?? 'Nominal';
        fanRpm = res['fan_rpm'] as int?;
        cpuSource = res['cpu_temp_source'] as String? ?? '';
        gpuSource = res['gpu_temp_source'] as String? ?? '';
      }
    } catch (_) {}

    final perCore = await _nativeCores();

    return SensorsSnapshot(
      cpuUsagePercent: cpu.clamp(0, 100).toDouble(),
      gpuUsagePercent: gpuUsage,
      ramUsedBytes: used,
      ramTotalBytes: total,
      temperatureC: cpuTemp ?? gpuTemp,
      cpuTemperatureC: cpuTemp,
      gpuTemperatureC: gpuTemp,
      cpuTempSource: cpuSource,
      gpuTempSource: gpuSource,
      perCoreUsage: perCore.loads,
      fanRpm: fanRpm,
      hasFan: hasFan,
      fanStatus: fanStatus,
      thermalState: thermalState,
    );
  }

  /// Núcleos individuais via canal nativo (macOS/Android).
  ///
  /// Devolve cargas em % quando o SO permite (`/proc/stat`) ou, no Android
  /// recente, a frequência por núcleo — o kernel bloqueia a carga.
  Future<_NativeCores> _nativeCores() async {
    try {
      final res =
          await _channel.invokeMapMethod<String, dynamic>('get_cpu_cores');
      if (res == null) return const _NativeCores();

      final mode = res['mode'] as String? ?? 'load';
      final loads = (res['loads'] as List?)
              ?.whereType<num>()
              .map((v) => v.toDouble().clamp(0.0, 100.0))
              .toList(growable: false) ??
          const <double>[];
      final frequencies = (res['frequencies'] as List?)
              ?.whereType<num>()
              .map((v) => v.toDouble())
              .toList(growable: false) ??
          const <double>[];
      final maxFrequency = (res['freq_max_mhz'] as num?)?.toDouble() ?? 0;

      return _NativeCores(
        loads: mode == 'load' ? loads : const [],
        frequencies: mode == 'frequency' ? frequencies : const [],
        maxFrequencyMhz: maxFrequency,
      );
    } catch (_) {
      return const _NativeCores();
    }
  }

  // --------------------------------------------------------------- Linux ---

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

    // CPU agregada e por núcleo em uma única leitura de /proc/stat
    double cpu = 0;
    var perCore = const <double>[];
    final times = await _readProcStat();
    if (times != null) {
      final previous = _previousProcStat;
      final aggregate = times.aggregate;
      if (aggregate != null) {
        final previousAggregate = previous?.aggregate;
        cpu = previousAggregate != null
            ? aggregate.usageSince(previousAggregate)
            : aggregate.usageSince(aggregate);
      }
      if (times.perCore.isNotEmpty) {
        final previousCores = previous?.perCore ?? const <CpuTicks>[];
        perCore = <double>[
          for (var i = 0; i < times.perCore.length; i++)
            i < previousCores.length
                ? times.perCore[i].usageSince(previousCores[i])
                : 0.0,
        ];
      }
      _previousProcStat = times;
    }

    final temps = await _linuxTemperatures();

    final cpuTemp = temps.cpu;
    final gpuTemp = temps.gpu;
    final hottest = [cpuTemp, gpuTemp].whereType<double>();
    final maxTemp = hottest.isEmpty
        ? null
        : hottest.reduce((a, b) => a > b ? a : b);

    return SensorsSnapshot(
      cpuUsagePercent: cpu,
      gpuUsagePercent: null,
      ramUsedBytes: used,
      ramTotalBytes: total,
      temperatureC: maxTemp,
      cpuTemperatureC: cpuTemp,
      gpuTemperatureC: gpuTemp,
      cpuTempSource: cpuTemp != null ? TempSource.sensor : '',
      gpuTempSource: gpuTemp != null ? TempSource.sensor : '',
      perCoreUsage: perCore,
      fanRpm: null,
      hasFan: true,
      fanStatus: 'Normal',
      thermalState: 'Nominal',
    );
  }

  /// Temperaturas reais no Linux via `/sys/class/thermal` e `/sys/class/hwmon`.
  Future<_LinuxTemps> _linuxTemperatures() async {
    double? cpu;
    double? gpu;

    // 1. hwmon: rótulos de CPU (coretemp/k10temp) e GPU (amdgpu/nouveau/i915/xe)
    try {
      final base = Directory('/sys/class/hwmon');
      if (base.existsSync()) {
        for (final driver in base.listSync()) {
          if (driver is! Directory) continue;
          final name = await _readFirstLine('${driver.path}/name');
          final chip = name.toLowerCase();
          final isCpuChip = chip.contains('coretemp') ||
              chip.contains('k10temp') ||
              chip.contains('zenpower') ||
              chip.contains('cpu');
          final isGpuChip = chip.contains('amdgpu') ||
              chip.contains('nouveau') ||
              chip.contains('i915') ||
              chip.contains('xe') ||
              chip.contains('radeon');
          if (!isCpuChip && !isGpuChip) continue;

          for (final entry in driver.listSync()) {
            final entityName = _basename(entry.path);
            if (!entityName.startsWith('temp') ||
                !entityName.endsWith('_input')) {
              continue;
            }
            final raw = await _readFirstLine(entry.path);
            final value = double.tryParse(raw);
            if (value == null) continue;
            final celsius = value > 1000 ? value / 1000 : value;
            if (celsius <= 0 || celsius > 150) continue;
            if (isGpuChip) {
              gpu = gpu == null || celsius > gpu ? celsius : gpu;
            } else {
              // Prefere Tctl/Tdie/Package quando existem.
              cpu = cpu == null || celsius > cpu ? celsius : cpu;
            }
          }
        }
      }
    } catch (_) {}

    // 2. thermal_zone: complementa o que faltar
    if (cpu == null || gpu == null) {
      try {
        final base = Directory('/sys/class/thermal');
        if (base.existsSync()) {
          for (final zone in base.listSync()) {
            if (!_basename(zone.path).startsWith('thermal_zone')) continue;
            final type = (await _readFirstLine('${zone.path}/type')).toLowerCase();
            final raw = double.tryParse(await _readFirstLine('${zone.path}/temp'));
            if (raw == null) continue;
            final celsius = raw > 1000 ? raw / 1000 : raw;
            if (celsius <= 0 || celsius > 150) continue;

            if (type.contains('gpu') || type.contains('g3d')) {
              final current = gpu;
              gpu = current == null || celsius > current ? celsius : current;
            } else if (type.contains('cpu') ||
                type.contains('core') ||
                type.contains('cluster') ||
                type.contains('pkg') ||
                type.contains('x86')) {
              final current = cpu;
              cpu = current == null || celsius > current ? celsius : current;
            }
          }
        }
      } catch (_) {}
    }

    return _LinuxTemps(
      cpu: cpu == null ? null : (cpu * 10).round() / 10.0,
      gpu: gpu == null ? null : (gpu * 10).round() / 10.0,
    );
  }

  Future<String> _readFirstLine(String path) async {
    try {
      final text = await File(path).readAsString();
      final line = text.split('\n').first.trim();
      return line;
    } catch (_) {
      return '';
    }
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  // -------------------------------------------------------------- Android ---

  Future<SensorsSnapshot> _collectAndroid() async {
    int total = 0;
    int used = 0;
    double? cpuTemp;
    double? gpuTemp;
    String cpuSource = '';
    String gpuSource = '';
    String thermalState = 'Nominal';
    String fanStatus = 'Passivo (Câmara de vapor)';
    double? headroom;

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('get_sensors');
      if (res != null) {
        total = (res['ram_total'] as num?)?.toInt() ?? 0;
        used = (res['ram_used'] as num?)?.toInt() ?? 0;
        cpuTemp = (res['cpu_temp'] as num?)?.toDouble();
        gpuTemp = (res['gpu_temp'] as num?)?.toDouble();
        cpuSource = res['cpu_temp_source'] as String? ?? '';
        gpuSource = res['gpu_temp_source'] as String? ?? '';
        fanStatus = res['fan_status'] as String? ?? fanStatus;
        thermalState = res['thermal_state'] as String? ?? thermalState;
        if (cpuTemp != null && cpuTemp <= 0) cpuTemp = null;
        if (gpuTemp != null && gpuTemp <= 0) gpuTemp = null;
        final rawHeadroom = (res['thermal_headroom'] as num?)?.toDouble();
        if (rawHeadroom != null && rawHeadroom > 0) headroom = rawHeadroom;
      }
    } catch (_) {}

    // Fallback de memória via /proc/meminfo caso canal nativo não responda
    if (total == 0) {
      try {
        final mem = await _run('cat', ['/proc/meminfo']);
        int kb(String key) {
          final m = RegExp('$key:\\s+(\\d+)').firstMatch(mem);
          return int.tryParse(m?.group(1) ?? '0') ?? 0;
        }

        total = kb('MemTotal') * 1024;
        final avail = kb('MemAvailable') * 1024;
        used = total > avail ? total - avail : 0;
      } catch (_) {}
    }

    // CPU agregada e por núcleo. Em Android recente o /proc/stat é bloqueado
    // para apps: nesse caso caímos para a frequência por núcleo do canal
    // nativo, que continua legível.
    double cpu = 0;
    var perCore = const <double>[];
    var coreFrequencies = const <double>[];
    var coreFrequencyMax = 0.0;
    var usageAvailable = false;

    final times = await _readProcStat();
    if (times != null) {
      final previous = _previousProcStat;
      final aggregate = times.aggregate;
      if (aggregate != null) {
        final previousAggregate = previous?.aggregate;
        cpu = previousAggregate != null
            ? aggregate.usageSince(previousAggregate)
            : aggregate.usageSince(aggregate);
        usageAvailable = true;
      }
      if (times.perCore.isNotEmpty) {
        final previousCores = previous?.perCore ?? const <CpuTicks>[];
        perCore = <double>[
          for (var i = 0; i < times.perCore.length; i++)
            i < previousCores.length
                ? times.perCore[i].usageSince(previousCores[i])
                : 0.0,
        ];
        usageAvailable = true;
      }
      _previousProcStat = times;
    }

    if (perCore.isEmpty && coreFrequencies.isEmpty) {
      final native = await _nativeCores();
      perCore = native.loads;
      coreFrequencies = native.frequencies;
      coreFrequencyMax = native.maxFrequencyMhz;
      if (perCore.isNotEmpty) {
        usageAvailable = true;
        cpu = perCore.reduce((a, b) => a + b) / perCore.length;
      }
    }

    final hottest = [cpuTemp, gpuTemp].whereType<double>();
    final maxTemp =
        hottest.isEmpty ? null : hottest.reduce((a, b) => a > b ? a : b);

    return SensorsSnapshot(
      cpuUsagePercent: cpu,
      gpuUsagePercent: null,
      ramUsedBytes: used,
      ramTotalBytes: total,
      temperatureC: maxTemp,
      cpuTemperatureC: cpuTemp,
      gpuTemperatureC: gpuTemp,
      cpuTempSource: cpuSource,
      gpuTempSource: gpuSource,
      perCoreUsage: perCore,
      perCoreFrequencyMhz: coreFrequencies,
      perCoreFrequencyMaxMhz: coreFrequencyMax,
      cpuUsageAvailable: usageAvailable,
      thermalHeadroom: headroom,
      fanRpm: null,
      hasFan: false,
      fanStatus: fanStatus,
      thermalState: thermalState,
    );
  }
}

/// Uma amostra de tempos de CPU (`/proc/stat`).
class CpuTicks {
  final int total;
  final int idle;

  const CpuTicks(this.total, this.idle);

  /// Percentual de uso (0-100) desde [previous].
  ///
  /// Sem amostra anterior válida devolve a média desde o boot, que é a única
  /// informação disponível na primeira leitura.
  double usageSince(CpuTicks previous) {
    final deltaTotal = total - previous.total;
    final deltaIdle = idle - previous.idle;
    if (deltaTotal <= 0) {
      if (total <= 0) return 0;
      return ((total - idle) / total * 100).clamp(0.0, 100.0);
    }
    final busy = (deltaTotal - deltaIdle).clamp(0, deltaTotal);
    return (busy / deltaTotal * 100).clamp(0.0, 100.0);
  }
}

/// Amostra completa de `/proc/stat`: linha agregada + uma por núcleo.
class CpuTimes {
  final CpuTicks? aggregate;
  final List<CpuTicks> perCore;

  const CpuTimes(this.aggregate, this.perCore);

  static CpuTimes? parse(String text) {
    CpuTicks? aggregate;
    final perCore = <CpuTicks>[];

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (!line.startsWith('cpu')) break; // /proc/stat começa com as linhas cpu*
      final space = line.indexOf(' ');
      if (space <= 0) continue;
      final label = line.substring(0, space);
      final fields = line
          .substring(space + 1)
          .trim()
          .split(RegExp(r'\s+'))
          .map((v) => int.tryParse(v) ?? 0)
          .toList();
      if (fields.length < 4) continue;

      // user nice system idle iowait irq softirq steal (guest fica de fora)
      final values = fields.take(8).toList();
      final idle = values[3] + (values.length > 4 ? values[4] : 0);
      final total = values.fold<int>(0, (a, b) => a + b);
      final ticks = CpuTicks(total, idle);

      if (label == 'cpu') {
        aggregate = ticks;
      } else {
        perCore.add(ticks);
      }
    }

    if (aggregate == null && perCore.isEmpty) return null;
    return CpuTimes(aggregate, perCore);
  }
}

/// Temperaturas do Linux (CPU e GPU separadas).
class _LinuxTemps {
  final double? cpu;
  final double? gpu;

  const _LinuxTemps({this.cpu, this.gpu});
}

/// Resultado do canal nativo de núcleos (macOS/Android).
class _NativeCores {
  final List<double> loads;
  final List<double> frequencies;
  final double maxFrequencyMhz;

  const _NativeCores({
    this.loads = const [],
    this.frequencies = const [],
    this.maxFrequencyMhz = 0,
  });
}
