import 'dart:io';

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

  /// Coleta os volumes montados. Retorna lista vazia em plataformas sem `df`.
  Future<List<StorageVolume>> collect() async {
    if (!(Platform.isMacOS || Platform.isLinux)) return const [];

    try {
      final result = await Process.run('df', ['-kP']);
      final out = (result.stdout as String?) ?? '';
      return parseDf(out);
    } catch (_) {
      return const [];
    }
  }
}
