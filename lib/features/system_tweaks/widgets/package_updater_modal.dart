import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../system_tweaks_models.dart';
import '../system_tweaks_service.dart';

enum _UpdatePhase { review, updating, finished }

/// Modal visual e amigável para atualização de pacotes do sistema
/// (Windows: winget, Linux: apt/dnf/pacman via Polkit).
class PackageUpdaterModal extends StatefulWidget {
  final SystemTweaksService service;
  final List<PackageInfoItem> initialPackages;
  final String packageManagerName;
  final VoidCallback? onCompleted;

  const PackageUpdaterModal({
    super.key,
    required this.service,
    required this.initialPackages,
    required this.packageManagerName,
    this.onCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required SystemTweaksService service,
    required List<PackageInfoItem> initialPackages,
    required String packageManagerName,
    VoidCallback? onCompleted,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PackageUpdaterModal(
        service: service,
        initialPackages: initialPackages,
        packageManagerName: packageManagerName,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<PackageUpdaterModal> createState() => _PackageUpdaterModalState();
}

class _PackageUpdaterModalState extends State<PackageUpdaterModal> {
  _UpdatePhase _phase = _UpdatePhase.review;
  final List<String> _logLines = [];
  final ScrollController _scrollController = ScrollController();
  bool _isSuccess = false;
  String _statusMessage = 'Aguardando início...';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startUpdate() async {
    setState(() {
      _phase = _UpdatePhase.updating;
      _statusMessage = 'Preparando ambiente de atualização...';
      _logLines.clear();
      _logLines.add('Iniciando atualização de pacotes via ${widget.packageManagerName}...');
    });

    final success = await widget.service.runPackageUpgrade(
      onProgress: (line) {
        if (!mounted) return;
        setState(() {
          _logLines.add(line);
          if (line.toLowerCase().contains('download') || line.toLowerCase().contains('baixando')) {
            _statusMessage = 'Baixando pacotes mais recentes...';
          } else if (line.toLowerCase().contains('install') || line.toLowerCase().contains('instalando')) {
            _statusMessage = 'Instalando atualizações no sistema...';
          } else if (line.toLowerCase().contains('sucesso') || line.toLowerCase().contains('successfully')) {
            _statusMessage = 'Concluído com sucesso!';
          }
        });
        _scrollToBottom();
      },
    );

    if (!mounted) return;
    setState(() {
      _isSuccess = success;
      _phase = _UpdatePhase.finished;
    });

    widget.onCompleted?.call();
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
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildPhaseContent(),
        ),
      ),
    );
  }

  Widget _buildPhaseContent() {
    switch (_phase) {
      case _UpdatePhase.review:
        return _buildReviewPhase();
      case _UpdatePhase.updating:
        return _buildUpdatingPhase();
      case _UpdatePhase.finished:
        return _buildFinishedPhase();
    }
  }

  Widget _buildReviewPhase() {
    final count = widget.initialPackages.length;

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
              child: const Icon(Icons.system_update_alt, color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Atualizador de Pacotes do Sistema',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count > 0
                        ? '$count pacotes disponíveis para atualização.'
                        : 'Atualizar todos os pacotes gerenciados pelo sistema.',
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
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gerenciador detectado: ${widget.packageManagerName}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: count > 0
              ? ListView.separated(
                  itemCount: count,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = widget.initialPackages[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderSoft),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.textMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  p.id,
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${p.currentVersion} → ${p.availableVersion}',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                p.source,
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, color: AppColors.green.withValues(alpha: 0.6), size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhuma atualização pendente detectada na lista prévia.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Você ainda pode clicar em Atualizar para verificar os repositórios online.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
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
              onPressed: _startUpdate,
              icon: const Icon(Icons.arrow_upward, size: 16),
              label: const Text('Atualizar Agora'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: const Color(0xFF04212A),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpdatingPhase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Atualizando Pacotes do Sistema',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: AppColors.accent, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const LinearProgressIndicator(
          backgroundColor: AppColors.cardAlt,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
        ),
        const SizedBox(height: 16),
        const Text(
          'Progresso de execução:',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF080D13),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _logLines.length,
              itemBuilder: (context, i) {
                final line = _logLines[i];
                final isError = line.startsWith('[ERRO]');
                final isWarning = line.startsWith('[AVISO]');
                final isSuccess = line.startsWith('✓');

                Color textColor = AppColors.textSecondary;
                if (isError) textColor = AppColors.red;
                if (isWarning) textColor = AppColors.orange;
                if (isSuccess) textColor = AppColors.green;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      color: textColor,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Aguarde a finalização do processo...',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            OutlinedButton(
              onPressed: null, // Desabilitado durante o processo
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                side: const BorderSide(color: AppColors.borderSoft),
              ),
              child: const Text('Processando...'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinishedPhase() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (_isSuccess ? AppColors.green : AppColors.orange).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isSuccess ? Icons.check_circle_outline : Icons.info_outline,
            color: _isSuccess ? AppColors.green : AppColors.orange,
            size: 48,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _isSuccess ? 'Atualização Concluída!' : 'Processo Finalizado',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isSuccess
              ? 'Os pacotes do sistema foram verificados e atualizados.'
              : 'O processo de atualização foi concluído. Verifique o log se houve pacotes cancelados.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 18),
        Container(
          height: 140,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF080D13),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: ListView.builder(
            itemCount: _logLines.length,
            itemBuilder: (context, i) {
              return Text(
                _logLines[i],
                style: const TextStyle(
                  fontFamily: 'Courier',
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: const Color(0xFF04212A),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
          ),
          child: const Text('Concluir'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
