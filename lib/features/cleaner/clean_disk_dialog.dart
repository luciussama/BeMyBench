library clean_disk_dialog;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'cleaner_models.dart';
import 'cleaner_service.dart';

enum _CleanPhase { scanning, review, cleaning, finished }

/// Diálogo modal interativo para varredura e limpeza segura de disco/SSD.
class CleanDiskDialog extends StatefulWidget {
  final VoidCallback? onCompleted;

  const CleanDiskDialog({super.key, this.onCompleted});

  static Future<void> show(BuildContext context, {VoidCallback? onCompleted}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CleanDiskDialog(onCompleted: onCompleted),
    );
  }

  @override
  State<CleanDiskDialog> createState() => _CleanDiskDialogState();
}

class _CleanDiskDialogState extends State<CleanDiskDialog> {
  final CleanerService _cleanerService = CleanerService();

  _CleanPhase _phase = _CleanPhase.scanning;
  CleanScanReport? _scanReport;
  CleanExecutionReport? _executionReport;
  final Set<CleanCategoryType> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _phase = _CleanPhase.scanning);
    try {
      final report = await _cleanerService.scanDisk();
      if (!mounted) return;

      final initialSelected = <CleanCategoryType>{};
      for (final cat in report.categories) {
        if (cat.fileCount > 0 && cat.isRecommended) {
          initialSelected.add(cat.categoryType);
        }
      }

      setState(() {
        _scanReport = report;
        _selectedCategories.addAll(initialSelected);
        _phase = _CleanPhase.review;
      });
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _startClean() async {
    if (_scanReport == null || _selectedCategories.isEmpty) return;

    setState(() => _phase = _CleanPhase.cleaning);
    try {
      final execReport = await _cleanerService.executeClean(
        selectedCategories: _selectedCategories,
        scanReport: _scanReport!,
      );
      if (!mounted) return;
      setState(() {
        _executionReport = execReport;
        _phase = _CleanPhase.finished;
      });
      widget.onCompleted?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _CleanPhase.review);
    }
  }

  int get _selectedBytes {
    if (_scanReport == null) return 0;
    int sum = 0;
    for (final cat in _scanReport!.categories) {
      if (_selectedCategories.contains(cat.categoryType)) {
        sum += cat.totalSizeBytes;
      }
    }
    return sum;
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
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildPhaseContent(),
        ),
      ),
    );
  }

  Widget _buildPhaseContent() {
    switch (_phase) {
      case _CleanPhase.scanning:
        return _buildScanningPhase();
      case _CleanPhase.review:
        return _buildReviewPhase();
      case _CleanPhase.cleaning:
        return _buildCleaningPhase();
      case _CleanPhase.finished:
        return _buildFinishedPhase();
    }
  }

  Widget _buildScanningPhase() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 32),
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
        SizedBox(height: 24),
        Text(
          'Analisando Mídia de Armazenamento...',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Examinando diretórios seguros de caches, temporários e relatórios órfãos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        SizedBox(height: 32),
      ],
    );
  }

  Widget _buildReviewPhase() {
    final report = _scanReport!;
    final selectedBytesFormatted = CategoryScanResult.formatBytes(_selectedBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cleaning_services_outlined, color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Limpeza Inteligente de Armazenamento',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Identificados ${report.totalSizeLabel} em ${report.totalFiles} itens descartáveis.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 18, color: AppColors.green),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Segurança ativa: apenas arquivos temporários e caches descartáveis são listados. Arquivos em uso pelo sistema serão preservados.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: report.categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final cat = report.categories[index];
              final isSelected = _selectedCategories.contains(cat.categoryType);
              final isAvailable = cat.fileCount > 0;

              return InkWell(
                onTap: isAvailable
                    ? () {
                        setState(() {
                          if (isSelected) {
                            _selectedCategories.remove(cat.categoryType);
                          } else {
                            _selectedCategories.add(cat.categoryType);
                          }
                        });
                      }
                    : null,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accent.withValues(alpha: 0.08) : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderSoft,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: AppColors.accent,
                        checkColor: const Color(0xFF04212A),
                        onChanged: isAvailable
                            ? (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedCategories.add(cat.categoryType);
                                  } else {
                                    _selectedCategories.remove(cat.categoryType);
                                  }
                                });
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Icon(cat.icon, size: 20, color: isAvailable ? AppColors.accent : AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cat.title,
                              style: TextStyle(
                                color: isAvailable ? AppColors.textPrimary : AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cat.description,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            cat.sizeLabel,
                            style: TextStyle(
                              color: isAvailable ? AppColors.textPrimary : AppColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${cat.fileCount} itens',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedCategories.length == report.categories.length) {
                    _selectedCategories.clear();
                  } else {
                    _selectedCategories.addAll(
                      report.categories.where((c) => c.fileCount > 0).map((c) => c.categoryType),
                    );
                  }
                });
              },
              child: Text(
                _selectedCategories.length == report.categories.length
                    ? 'Desmarcar Todos'
                    : 'Selecionar Todos',
                style: const TextStyle(color: AppColors.accent, fontSize: 12),
              ),
            ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _selectedCategories.isEmpty ? null : _startClean,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Limpar Agora ($selectedBytesFormatted)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF04212A),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCleaningPhase() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 32),
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
          ),
        ),
        SizedBox(height: 24),
        Text(
          'Removendo Arquivos Selecionados...',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Garantindo que arquivos em uso ou abertos pelo sistema operacional sejam preservados.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        SizedBox(height: 32),
      ],
    );
  }

  Widget _buildFinishedPhase() {
    final report = _executionReport!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline, color: AppColors.green, size: 48),
        ),
        const SizedBox(height: 20),
        Text(
          '${report.bytesFreedLabel} Liberados!',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Foram removidos ${report.filesDeleted} arquivos com sucesso em ${report.durationMs} ms.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        if (report.errorsCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${report.errorsCount} arquivos estavam em uso pelo sistema e foram mantidos por segurança.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: const Color(0xFF04212A),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          child: const Text('Concluir'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
