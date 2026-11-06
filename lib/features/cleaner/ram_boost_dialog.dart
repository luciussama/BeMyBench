library ram_boost_dialog;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'cleaner_models.dart';
import 'cleaner_service.dart';

enum _BoostPhase { running, finished }

/// Diálogo modal com animação e telemetria para o Boost de RAM.
class RamBoostDialog extends StatefulWidget {
  final VoidCallback? onCompleted;

  const RamBoostDialog({super.key, this.onCompleted});

  static Future<void> show(BuildContext context, {VoidCallback? onCompleted}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => RamBoostDialog(onCompleted: onCompleted),
    );
  }

  @override
  State<RamBoostDialog> createState() => _RamBoostDialogState();
}

class _RamBoostDialogState extends State<RamBoostDialog> {
  final CleanerService _cleanerService = CleanerService();

  _BoostPhase _phase = _BoostPhase.running;
  RamBoostReport? _report;

  @override
  void initState() {
    super.initState();
    _executeBoost();
  }

  Future<void> _executeBoost() async {
    setState(() => _phase = _BoostPhase.running);
    try {
      final rep = await _cleanerService.boostRam();
      if (!mounted) return;
      setState(() {
        _report = rep;
        _phase = _BoostPhase.finished;
      });
      widget.onCompleted?.call();
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _phase == _BoostPhase.running ? _buildRunningContent() : _buildFinishedContent(),
        ),
      ),
    );
  }

  Widget _buildRunningContent() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: 16),
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.orange),
          ),
        ),
        SizedBox(height: 24),
        Text(
          'Otimizando Memória RAM...',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Purgando caches de disco inativos, compactando buffers e devolvendo blocos ao sistema.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFinishedContent() {
    final report = _report!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.bolt, color: AppColors.orange, size: 44),
        ),
        const SizedBox(height: 20),
        Text(
          report.bytesFreed > 0 ? '${report.bytesFreedLabel} Liberados!' : 'Memória RAM Otimizada!',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'A memória inativa e os buffers em segundo plano foram devolvidos ao sistema.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Antes do Boost', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(
                      '${report.usedBeforeLabel} (${report.percentBefore.toStringAsFixed(0)}%)',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: AppColors.borderSoft),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Após o Boost', style: TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${report.usedAfterLabel} (${report.percentAfter.toStringAsFixed(0)}%)',
                      style: const TextStyle(
                        color: AppColors.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF101B24),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Método: ${report.methodUsed}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 4),
              Text(
                'Tempo de execução: ${report.durationMs} ms',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: const Color(0xFF04212A),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
          ),
          child: const Text('Concluir'),
        ),
      ],
    );
  }
}
