import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'system_tweaks_models.dart';
import 'system_tweaks_service.dart';
import 'widgets/package_updater_modal.dart';

/// Tela principal da aba "Ajustes" (Ajustes do Sistema).
/// Implementa os 3 pilares:
/// 1. Atualização de pacotes do SO (botão interativo com modal visual)
/// 2. Varredura por drivers disponíveis
/// 3. Exibição de hardware com driver não localizado ou com falha
class SystemTweaksScreen extends StatefulWidget {
  final SystemTweaksService? service;

  const SystemTweaksScreen({super.key, this.service});

  @override
  State<SystemTweaksScreen> createState() => _SystemTweaksScreenState();
}

class _SystemTweaksScreenState extends State<SystemTweaksScreen> {
  late final SystemTweaksService _service;
  bool _isLoading = true;
  SystemTweaksScanReport? _report;
  bool _isCheckingDrivers = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SystemTweaksService();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _isLoading = true);
    final report = await _service.fullDiagnosticsScan();
    if (!mounted) return;
    setState(() {
      _report = report;
      _isLoading = false;
    });
  }

  Future<void> _refreshDriversOnly() async {
    setState(() => _isCheckingDrivers = true);
    final drivers = await _service.scanDriverUpdates();
    if (!mounted) return;
    if (_report != null) {
      setState(() {
        _report = SystemTweaksScanReport(
          timestamp: DateTime.now(),
          osName: _report!.osName,
          packageManagerName: _report!.packageManagerName,
          isPackageManagerAvailable: _report!.isPackageManagerAvailable,
          availablePackages: _report!.availablePackages,
          availableDrivers: drivers,
          problematicHardware: _report!.problematicHardware,
          scanDurationMs: _report!.scanDurationMs,
        );
        _isCheckingDrivers = false;
      });
    } else {
      setState(() => _isCheckingDrivers = false);
    }
  }

  void _openPackageUpdater() {
    if (_report == null) return;
    PackageUpdaterModal.show(
      context,
      service: _service,
      initialPackages: _report!.availablePackages,
      packageManagerName: _report!.packageManagerName,
      onCompleted: _loadDiagnostics,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Examinando subsistemas de hardware, drivers e pacotes...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final report = _report!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(report),
            const SizedBox(height: 20),

            // PILAR 3: Exibição de hardware com driver não localizado ou com problemas
            _buildHardwareIssuesSection(report),
            const SizedBox(height: 20),

            // PILAR 2: Vasculhar por atualização de driver
            _buildDriverUpdatesSection(report),
            const SizedBox(height: 20),

            // PILAR 1: Atualização de pacotes do sistema
            _buildPackageUpdatesSection(report),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CABEÇALHO
  // ===========================================================================

  Widget _buildHeader(SystemTweaksScanReport report) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.tune_rounded, color: AppColors.accent, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Ajustes do Sistema',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      report.osName,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Diagnóstico de integridade de drivers, varredura de hardware e atualização de pacotes.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loadDiagnostics,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Reescanear'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PILAR 3: HARDWARE COM DRIVER AUSENTE OU COM PROBLEMAS
  // ===========================================================================

  Widget _buildHardwareIssuesSection(SystemTweaksScanReport report) {
    final issues = report.problematicHardware;
    final hasIssues = issues.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasIssues ? AppColors.orange.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasIssues ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: hasIssues ? AppColors.orange : AppColors.green,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasIssues
                          ? 'Hardware com Driver Não Localizado ou Falha Operacional'
                          : 'Diagnóstico de Dispositivos e Drivers',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasIssues
                          ? 'Foram identificados ${issues.length} dispositivo(s) que requerem atenção técnica.'
                          : 'Todos os dispositivos de hardware estão funcionando corretamente e com drivers ativos.',
                      style: TextStyle(
                        color: hasIssues ? AppColors.orange : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (hasIssues ? AppColors.orange : AppColors.green).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasIssues ? '${issues.length} com alerta' : '100% íntegro',
                  style: TextStyle(
                    color: hasIssues ? AppColors.orange : AppColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (hasIssues) ...[
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: issues.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = issues[i];
                final isMissingDriver = item.severity == HardwareProblemSeverity.missingDriver;
                final badgeColor = isMissingDriver ? AppColors.orange : AppColors.red;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isMissingDriver ? Icons.help_outline : Icons.error_outline,
                            color: badgeColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.errorTitle,
                              style: TextStyle(
                                color: badgeColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.errorDescription,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lightbulb_outline, size: 14, color: AppColors.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.suggestedAction,
                              style: const TextStyle(color: AppColors.accent, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // PILAR 2: VARREDURA POR ATUALIZAÇÃO DE DRIVER
  // ===========================================================================

  Widget _buildDriverUpdatesSection(SystemTweaksScanReport report) {
    final drivers = report.availableDrivers;
    final hasDrivers = drivers.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.developer_board, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Atualizações de Drivers de Hardware',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDrivers
                          ? '${drivers.length} atualização(ões) de driver disponível(is) para seus componentes.'
                          : 'Seus drivers estão atualizados de acordo com os repositórios oficiais.',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isCheckingDrivers ? null : _refreshDriversOnly,
                icon: _isCheckingDrivers
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary),
                      )
                    : const Icon(Icons.search, size: 16),
                label: Text(_isCheckingDrivers ? 'Pesquisando...' : 'Pesquisar Drivers'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentDeep,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
          if (hasDrivers) ...[
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: drivers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = drivers[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        d.isFirmware ? Icons.memory : Icons.settings_input_component,
                        color: AppColors.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.deviceName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${d.manufacturer} • ${d.provider}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              d.availableVersion,
                              style: const TextStyle(
                                color: AppColors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (d.releaseDate != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              d.releaseDate!,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ] else ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.done_all, color: AppColors.green, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Nenhum driver pendente detectado no momento pelo gerenciador de hardware.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // PILAR 1: ATUALIZAÇÃO DE PACOTES DO SISTEMA
  // ===========================================================================

  Widget _buildPackageUpdatesSection(SystemTweaksScanReport report) {
    // Se a plataforma não possuir suporte a gerenciador de pacotes, omite o recurso sem disclaimer
    if (!report.isPackageManagerAvailable) {
      return const SizedBox.shrink();
    }

    final count = report.availablePackages.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.system_update_alt, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Atualização de Pacotes do Sistema',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gerenciador ativo: ${report.packageManagerName}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: report.isPackageManagerAvailable ? _openPackageUpdater : null,
                icon: const Icon(Icons.download, size: 16),
                label: Text(count > 0 ? 'Atualizar Pacotes ($count)' : 'Atualizar Pacotes'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: const Color(0xFF04212A),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            count > 0
                ? 'Existem $count pacotes com novas versões disponíveis nos repositórios oficiais.'
                : 'O botão acima realiza a verificação completa e atualização dos pacotes em janela visual interativa.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
