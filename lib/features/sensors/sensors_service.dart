import 'dart:io';

/// Leitura de sensores sem dependências externas.
///
/// macOS: `top` (uso de CPU), `vm_stat` + `hw.memsize` (RAM).
/// Temperatura/ventoinha no Apple Silicon são limitadas pelo sistema;
/// ficam como "N/A" com aviso (powermetrics exige sudo).
class SensorsSnapshot {
  final double cpuUsagePercent;
  final int ramUsedBytes;
  final int ramTotalBytes;
  final double? temperatureC;
  final int? fanRpm;

  const SensorsSnapshot({
    required this.cpuUsagePercent,
    required this.ramUsedBytes,
    required this.ramTotalBytes,
    this.temperatureC,
    this.fanRpm,
  });

  double get ramUsagePercent =>
      ramTotalBytes == 0 ? 0 : (ramUsedBytes / ramTotalBytes) * 100;

  String get ramUsedLabel => _gb(ramUsedBytes);
  String get ramTotalLabel => _gb(ramTotalBytes);

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class SensorsService {
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

    return SensorsSnapshot(
      cpuUsagePercent: cpu.clamp(0, 100).toDouble(),
      ramUsedBytes: used,
      ramTotalBytes: total,
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
      // Duas leituras de /proc/stat com 500ms de intervalo
      Future<List<int>> readStat() async {
        final s = await _run('cat', ['/proc/stat']);
        final first = s.split('\n').first.split(RegExp(r'\s+'));
        return first.skip(1).take(7).map(int.parse).toList();
      }

      final a = await readStat();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final b = await readStat();
      final aTotal = a.fold<int>(0, (p, e) => p + e);
      final bTotal = b.fold<int>(0, (p, e) => p + e);
      final aIdle = a[3] + (a.length > 4 ? a[4] : 0);
      final bIdle = b[3] + (b.length > 4 ? b[4] : 0);
      final dTotal = bTotal - aTotal;
      final dIdle = bIdle - aIdle;
      if (dTotal > 0) cpu = ((dTotal - dIdle) / dTotal) * 100;
    } catch (_) {}

    return SensorsSnapshot(
      cpuUsagePercent: cpu.clamp(0, 100).toDouble(),
      ramUsedBytes: (total - available).clamp(0, total),
      ramTotalBytes: total,
    );
  }
}
