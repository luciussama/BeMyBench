import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'sensors_service.dart';

/// Quadro de monitoramento da CPU separado por núcleo lógico.
///
/// Exibe a utilização de cada thread lógica quando o SO permite ler
/// `/proc/stat`. Em plataformas que bloqueiam essa leitura (Android 12+), cai
/// para a frequência atual de cada núcleo — telemetria real, sem inventar
/// percentuais. Quando nem isso existe, explica o motivo.
class CpuCoresPanel extends StatelessWidget {
  final SensorsSnapshot snapshot;

  const CpuCoresPanel({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final frequencyMode = snapshot.hasPerCoreFrequency;
    final hasCores = snapshot.hasPerCore;
    final count = snapshot.coreCount;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                frequencyMode ? Icons.speed : Icons.grid_view_rounded,
                size: 16,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  frequencyMode
                      ? 'Frequência da CPU por núcleo'
                      : 'Utilização da CPU por núcleo',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasCores)
                Text(
                  '$count núcleos lógicos',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasCores
                ? (frequencyMode
                    ? 'Frequência atual de cada thread lógica. Nesta plataforma '
                        'o SO bloqueia a leitura de uso por núcleo, então a '
                        'frequência é a telemetria granular disponível.'
                    : 'Carga individual de cada thread lógica da CPU, medida '
                        'desde a amostra anterior (atualizada a cada 2 segundos).')
                : 'A leitura por núcleo não está disponível nesta plataforma.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          if (hasCores) ...[
            const SizedBox(height: 14),
            _Summary(snapshot: snapshot, frequencyMode: frequencyMode),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _cards(frequencyMode),
            ),
          ] else if (Platform.isAndroid)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'O Android restringe /proc/stat e /sys/class/thermal para apps '
                '(SELinux). O aparelho não expôs nem a carga nem a frequência '
                'por núcleo.',
                style: TextStyle(
                  color: AppColors.orange,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _cards(bool frequencyMode) {
    if (frequencyMode) {
      final reference = snapshot.perCoreFrequencyReference;
      final frequencies = snapshot.perCoreFrequencyMhz;
      final peak = frequencies.isEmpty
          ? 0
          : frequencies.reduce((a, b) => a > b ? a : b);
      return [
        for (var i = 0; i < frequencies.length; i++)
          _CoreCard(
            index: i,
            ratio: reference <= 0 ? 0 : frequencies[i] / reference,
            label: _frequencyLabel(frequencies[i]),
            color: AppColors.accent,
            isPeak: frequencies[i] >= peak && peak > 0,
          ),
      ];
    }

    final cores = snapshot.perCoreUsage;
    return [
      for (var i = 0; i < cores.length; i++)
        _CoreCard(
          index: i,
          ratio: cores[i] / 100,
          label: '${cores[i].toStringAsFixed(0)}%',
          color: AppColors.loadColor(cores[i]),
          isPeak: i == snapshot.perCorePeakIndex && snapshot.perCorePeak >= 5,
        ),
    ];
  }

  static String _frequencyLabel(double mhz) {
    if (mhz >= 1000) return '${(mhz / 1000).toStringAsFixed(2)} GHz';
    return '${mhz.toStringAsFixed(0)} MHz';
  }
}

class _Summary extends StatelessWidget {
  final SensorsSnapshot snapshot;
  final bool frequencyMode;

  const _Summary({required this.snapshot, required this.frequencyMode});

  @override
  Widget build(BuildContext context) {
    if (frequencyMode) {
      final frequencies = snapshot.perCoreFrequencyMhz;
      final average = frequencies.isEmpty
          ? 0.0
          : frequencies.reduce((a, b) => a + b) / frequencies.length;
      final peak = frequencies.isEmpty
          ? 0.0
          : frequencies.reduce((a, b) => a > b ? a : b);
      final reference = snapshot.perCoreFrequencyReference;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SummaryPill(
            label: 'Média',
            value: CpuCoresPanel._frequencyLabel(average),
            color: AppColors.accent,
          ),
          _SummaryPill(
            label: 'Máxima',
            value: CpuCoresPanel._frequencyLabel(peak),
            color: AppColors.orange,
          ),
          _SummaryPill(
            label: 'Referência',
            value: reference > 0
                ? CpuCoresPanel._frequencyLabel(reference)
                : 'N/A',
            color: AppColors.violet,
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryPill(
          label: 'Média',
          value: '${snapshot.perCoreAverage.toStringAsFixed(1)}%',
          color: AppColors.accent,
        ),
        _SummaryPill(
          label: 'Pico (N${snapshot.perCorePeakIndex})',
          value: '${snapshot.perCorePeak.toStringAsFixed(0)}%',
          color: AppColors.loadColor(snapshot.perCorePeak),
        ),
        _SummaryPill(
          label: 'Ociosos',
          value:
              '${snapshot.perCoreUsage.where((v) => v < 5).length}/${snapshot.coreCount}',
          color: AppColors.green,
        ),
        _SummaryPill(
          label: 'Saturados',
          value:
              '${snapshot.perCoreUsage.where((v) => v >= 90).length}/${snapshot.coreCount}',
          color: AppColors.orange,
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoreCard extends StatelessWidget {
  final int index;
  final double ratio;
  final String label;
  final Color color;
  final bool isPeak;

  const _CoreCard({
    required this.index,
    required this.ratio,
    required this.label,
    required this.color,
    required this.isPeak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isPeak ? color.withValues(alpha: 0.55) : AppColors.borderSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'N$index',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
