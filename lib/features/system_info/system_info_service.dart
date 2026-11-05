import 'dart:io';

/// Leitura de System Info sem dependências externas (MVP).
///
/// macOS/Linux: usa sysctl / /proc / sw_vers via Process.
/// Windows/Android: stubs até os MethodChannels nativos serem implementados.
class SystemInfoService {
  Future<Map<String, String>> collect() async {
    final Map<String, String> data = {};
    data['OS'] = _osName();

    if (Platform.isMacOS) {
      await _collectMac(data);
    } else if (Platform.isLinux) {
      await _collectLinux(data);
    } else if (Platform.isWindows) {
      await _collectWindowsStub(data);
    } else if (Platform.isAndroid) {
      await _collectAndroidStub(data);
    } else {
      data['CPU'] = 'N/A';
      data['RAM'] = 'N/A';
    }
    return data;
  }

  String _osName() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'unknown';
  }

  Future<String> _run(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args, runInShell: false);
      return (r.stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  Future<String> _sysctl(String key) async => _run('sysctl', ['-n', key]);

  Future<void> _collectMac(Map<String, String> d) async {
    final cpuBrand = await _sysctl('machdep.cpu.brand_string');
    final ncpu = await _sysctl('hw.ncpu');
    final phys = await _sysctl('hw.physicalcpu');
    final logical = await _sysctl('hw.logicalcpu');
    final memBytesRaw = await _sysctl('hw.memsize');
    final memBytes = int.tryParse(memBytesRaw);
    final disk = await _run('df', ['-h', '/']);
    final swVers = await _run('sw_vers', ['-productVersion']);

    d['CPU'] = cpuBrand.isNotEmpty ? cpuBrand : 'Apple Silicon / Intel';
    d['Cores'] = '${phys.isNotEmpty ? phys : '?'} físicos / ${logical.isNotEmpty ? logical : ncpu} lógicos';
    d['RAM total'] = memBytes != null
        ? '${(memBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
        : 'N/A';
    d['macOS versão'] = swVers.isNotEmpty ? swVers : 'N/A';
    d['Disco (/)'] = disk.split('\n').last;
    d['GPU'] = 'Ver system_profiler (a implementar)';
  }

  Future<void> _collectLinux(Map<String, String> d) async {
    final memInfo = await _run('free', ['-h']);
    final cpuInfo = await _run('lscpu', []);
    d['CPU'] = cpuInfo.split('\n').first.replaceFirst('Model name:', '').trim();
    d['Memória'] = memInfo.split('\n').where((l) => l.startsWith('Mem:')).firstOrNull ?? 'N/A';
    d['GPU'] = 'a implementar (lspci / vulkaninfo)';
  }

  Future<void> _collectWindowsStub(Map<String, String> d) async {
    d['CPU'] = 'a implementar via WMI (Win32_Processor)';
    d['RAM total'] = 'a implementar via WMI (Win32_ComputerSystem)';
    d['GPU'] = 'a implementar via WMI (Win32_VideoController)';
  }

  Future<void> _collectAndroidStub(Map<String, String> d) async {
    d['CPU'] = 'a implementar via /proc/cpuinfo + Build';
    d['RAM total'] = 'a implementar via ActivityManager';
    d['GPU'] = 'a implementar via GLES';
  }
}
