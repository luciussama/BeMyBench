import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'storage_service.dart';

/// Painel de armazenamento: uso de cada volume montado (leitura direta do
/// sistema de arquivos). Nada é escrito; é apenas uma visão geral.
class StoragePanel extends StatefulWidget {
  const StoragePanel({super.key});

  @override
  State<StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<StoragePanel> {
  final _service = StorageService();

  List<StorageVolume> _volumes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final volumes = await _service.collect();
    if (!mounted) return;
    setState(() {
      _volumes = volumes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_outlined,
                  size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Armazenamento por volume',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading) ...[
            const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
          ] else if (_volumes.isEmpty) ...[
            const Text(
              'Nenhum volume montado disponível para leitura neste sistema.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ] else ...[
            for (final v in _volumes) ...[
              _VolumeRow(volume: v),
              if (v != _volumes.last) const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            const Text(
              'Em APFS, "/" e "/System/Volumes/Data" compartilham o mesmo '
              'contêiner físico; os totais somam o mesmo espaço.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final StorageVolume volume;

  const _VolumeRow({required this.volume});

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final critical = volume.isCritical;
    final barColor = critical ? AppColors.red : AppColors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder_outlined,
                size: 14, color: critical ? AppColors.red : AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                volume.label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${_fmtBytes(volume.usedBytes)} / ${_fmtBytes(volume.totalBytes)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: volume.usedFraction,
            minHeight: 6,
            backgroundColor: AppColors.borderSoft,
            color: barColor,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                volume.mount,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${volume.capacityPercent}% usado · ${_fmtBytes(volume.freeBytes)} livres',
              style: TextStyle(
                color: critical ? AppColors.red : AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
