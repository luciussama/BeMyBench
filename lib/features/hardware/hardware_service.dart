import 'dart:io';

/// Dados estáticos de hardware do dispositivo (coletados uma vez).
class HardwareInfo {
  final String hostname;
  final String osName;
  final String osVersion;
  final String kernel;
  final String arch;
  final String model;
  final String chip;
  final int cores;
  final int ramTotalBytes;
  final int diskTotalBytes;
  final int diskFreeBytes;

  const HardwareInfo({
    required this.hostname,
    required this.osName,
    required this.osVersion,
    required this.kernel,
    required this.arch,
    required this.model,
    required this.chip,
    required this.cores,
    required this.ramTotalBytes,
    required this.diskTotalBytes,
    required this.diskFreeBytes,
  });

  String get osLabel => '$osName $osVersion';
  String get archLabel => arch.contains('arm64') ? 'ARM64 (Apple Silicon)' : arch;

  double get diskFreePercent =>
      diskTotalBytes == 0 ? 0 : diskFreeBytes / diskTotalBytes * 100;

  String get ramTotalLabel =>
      '${(ramTotalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';

  String get diskTotalLabel => _gb(diskTotalBytes);
  String get diskFreeLabel => _gb(diskFreeBytes);

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
}

class HardwareService {
  Future<HardwareInfo> collect() async {
    if (Platform.isMacOS) return _collectMac();
    return _collectGeneric();
  }

  Future<String> _run(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args);
      return (r.stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  Future<HardwareInfo> _collectMac() async {
    final results = await Future.wait([
      _run('sw_vers', ['-productName']),
      _run('sw_vers', ['-productVersion']),
      _run('uname', ['-r']),
      _run('uname', ['-m']),
      _run('sysctl', ['-n', 'hw.model']),
      _run('sysctl', ['-n', 'hw.ncpu']),
      _run('sysctl', ['-n', 'hw.memsize']),
      _run('system_profiler', ['SPHardwareDataType']),
      _run('df', ['-k', '/']),
    ]);

    final osName = results[0].isEmpty ? 'macOS' : results[0];
    final osVersion = results[1];
    final kernel = results[2];
    final arch = results[3];
    final model = results[4];
    final cores = int.tryParse(results[5]) ?? 0;
    final ram = int.tryParse(results[6]) ?? 0;

    String chip = 'Apple Silicon';
    final sp = results[7];
    final chipMatch = RegExp(r'Chip:\s*(.+)').firstMatch(sp) ??
        RegExp(r'Processor Name:\s*(.+)').firstMatch(sp);
    if (chipMatch != null) chip = chipMatch.group(1)!.trim();

    int diskTotal = 0;
    int diskFree = 0;
    final lines = results[8].split('\n');
    if (lines.length > 1) {
      final parts = lines[1].trim().split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        diskTotal = (int.tryParse(parts[1]) ?? 0) * 1024;
        diskFree = (int.tryParse(parts[3]) ?? 0) * 1024;
      }
    }

    return HardwareInfo(
      hostname: Platform.localHostname,
      osName: osName,
      osVersion: osVersion,
      kernel: kernel,
      arch: arch,
      model: model,
      chip: chip,
      cores: cores,
      ramTotalBytes: ram,
      diskTotalBytes: diskTotal,
      diskFreeBytes: diskFree,
    );
  }

  Future<HardwareInfo> _collectGeneric() async {
    final osName = Platform.operatingSystem;
    return HardwareInfo(
      hostname: Platform.localHostname,
      osName: osName[0].toUpperCase() + osName.substring(1),
      osVersion: Platform.operatingSystemVersion,
      kernel: Platform.operatingSystemVersion,
      arch: Platform.version,
      model: 'N/A',
      chip: 'N/A',
      cores: Platform.numberOfProcessors,
      ramTotalBytes: 0,
      diskTotalBytes: 0,
      diskFreeBytes: 0,
    );
  }
}
