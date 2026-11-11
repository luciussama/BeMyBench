import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Um volume montado (partição/dispositivo) com uso de espaço.
class StorageVolume {
  final String filesystem;
  final String mount;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int capacityPercent;

  const StorageVolume({
    required this.filesystem,
    required this.mount,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.capacityPercent,
  });

  /// Nome amigável do volume (basename do ponto de montagem).
  String get label {
    if (mount == '/') return 'Raiz (/)';
    if (mount.contains(':')) return mount; // Windows C:, D:, etc.
    if (mount.contains('Armazenamento Interno')) return 'Armazenamento Interno';
    final trimmed = mount.endsWith('/') && mount.length > 1
        ? mount.substring(0, mount.length - 1)
        : mount;
    final parts = trimmed.split('/');
    return parts.last.isEmpty ? trimmed : parts.last;
  }

  double get usedFraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);

  bool get isCritical => capacityPercent >= 85;
}

class StorageService {
  /// Parseia a saída de `df -kP` (formato POSIX, cabeçalho único).
  /// Exposto para testes.
  static List<StorageVolume> parseDf(String output) {
    final volumes = <StorageVolume>[];

    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.toLowerCase().startsWith('filesystem')) continue;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 6) continue;

      final fs = parts[0];
      final total = int.tryParse(parts[1]) ?? 0;
      final used = int.tryParse(parts[2]) ?? 0;
      final avail = int.tryParse(parts[3]) ?? 0;
      final capacity = parts[4];
      final mount = parts.last;

      // Ignora pseudo-filesystems e montagens automáticas
      if (!mount.startsWith('/')) continue;
      if (fs == 'devfs' ||
          fs.startsWith('map ') ||
          fs.startsWith('map\t') ||
          fs == 'auto_home' ||
          fs.startsWith('autofs')) {
        continue;
      }
      if (total <= 0) continue;

      final percent = int.tryParse(capacity.replaceAll('%', '')) ??
          (used <= 0 ? 0 : (used * 100 / total).round());

      volumes.add(
        StorageVolume(
          filesystem: fs,
          mount: mount,
          totalBytes: total * 1024,
          usedBytes: used * 1024,
          freeBytes: avail * 1024,
          capacityPercent: percent,
        ),
      );
    }

    // Raiz primeiro, depois os demais volumes por ponto de montagem.
    volumes.sort((a, b) {
      if (a.mount == '/') return -1;
      if (b.mount == '/') return 1;
      return a.mount.compareTo(b.mount);
    });

    return volumes;
  }

  /// Coleta os volumes montados (macOS/Linux via df, Windows via WMI, Android via StatFs).
  Future<List<StorageVolume>> collect() async {
    if (Platform.isWindows) {
      return _collectWindows();
    }
    if (Platform.isAndroid) {
      return _collectAndroid();
    }
    if (!(Platform.isMacOS || Platform.isLinux)) return const [];

    try {
      final result = await Process.run('df', ['-kP']);
      final out = (result.stdout as String?) ?? '';
      return parseDf(out);
    } catch (_) {
      return const [];
    }
  }

  Future<List<StorageVolume>> _collectAndroid() async {
    try {
      const channel = MethodChannel('bemybench/platform');
      final res = await channel.invokeMapMethod<String, dynamic>('get_hardware');
      if (res != null) {
        final total = (res['storageTotalBytes'] as num?)?.toInt() ?? 0;
        final free = (res['storageFreeBytes'] as num?)?.toInt() ?? 0;
        if (total > 0) {
          final used = (total - free).clamp(0, total);
          final percent = ((used / total) * 100).round();
          return [
            StorageVolume(
              filesystem: 'F2FS Flash Storage',
              mount: 'Armazenamento Interno (/data)',
              totalBytes: total,
              usedBytes: used,
              freeBytes: free,
              capacityPercent: percent,
            ),
          ];
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<List<StorageVolume>> _collectWindows() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, VolumeName, Size, FreeSpace, FileSystem | ConvertTo-Json',
      ]);
      final out = (r.stdout as String).trim();
      if (out.isEmpty) return const [];

      final decoded = jsonDecode(out);
      final list = decoded is List ? decoded : [decoded];
      final volumes = <StorageVolume>[];

      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final devId = item['DeviceID']?.toString() ?? '';
        final volName = item['VolumeName']?.toString() ?? '';
        final fs = item['FileSystem']?.toString() ?? 'NTFS';
        final size = (item['Size'] as num?)?.toInt() ?? 0;
        final free = (item['FreeSpace'] as num?)?.toInt() ?? 0;
        if (size <= 0) continue;

        final used = size - free;
        final percent = (used * 100 / size).round();
        final mountLabel = volName.isNotEmpty ? '$volName ($devId)' : devId;

        volumes.add(
          StorageVolume(
            filesystem: fs,
            mount: mountLabel,
            totalBytes: size,
            usedBytes: used,
            freeBytes: free,
            capacityPercent: percent,
          ),
        );
      }
      return volumes;
    } catch (_) {
      return const [];
    }
  }
}
