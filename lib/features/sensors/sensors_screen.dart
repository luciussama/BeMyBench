import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'cpu_cores_panel.dart';
import 'sensors_service.dart';

class SensorsScreen extends StatefulWidget {
  /// Snapshot fixo usado em testes e na pré-visualização visual; em produção
  /// a tela coleta os dados sozinha.
  @visibleForTesting
  final SensorsSnapshot? debugSnapshot;

  const SensorsScreen({super.key, this.debugSnapshot});

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  final _service = SensorsService();
  SensorsSnapshot? _snapshot;
  Timer? _timer;
  bool _loading = true;
  bool _paused = false;

  final List<double> _cpuHistory = [];
  final List<double> _ramHistory = [];

  @override
  void initState() {
    super.initState();
    final injected = widget.debugSnapshot;
    if (injected != null) {
      _snapshot = injected;
      _loading = false;
      _cpuHistory.add(injected.cpuUsagePercent);
      _ramHistory.add(injected.ramUsagePercent);
      return;
    }
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_paused) _tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      final s = await _service.collect();
      if (!mounted) return;
      setState(() {
        _snapshot = s;
        _loading = false;
        _cpuHistory.add(s.cpuUsagePercent);
        _ramHistory.add(s.ramUsagePercent);
        if (_cpuHistory.length > 60) _cpuHistory.removeAt(0);
        if (_ramHistory.length > 60) _ramHistory.removeAt(0);
      });
    } catch (_) {}
  }

  Color _tempColor(double? temp) {
    if (temp == null) return AppColors.textSecondary;
    if (temp < 60) return AppColors.green;
    if (temp < 80) return AppColors.orange;
    return AppColors.red;
  }

  String _tempLabel(double? temp) =>
      temp == null ? 'N/A' : '${temp.toStringAsFixed(0)} °C';

  /// Legenda de uma temperatura: origem (sensor/estimado) e detalhe opcional.
  String _tempCaption(String source, {String? extra}) {
    final parts = <String>[];
    final sourceLabel = TempSource.label(source);
    if (sourceLabel.isNotEmpty) parts.add(sourceLabel);
    if (extra != null && extra.isNotEmpty) parts.add(extra);
    return parts.isEmpty ? 'sem leitura' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = _snapshot!;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppPanel(
          padding: const EdgeInsets.all(22),
          child: SectionHeader(
            icon: Icons.monitor_heart_outlined,
            eyebrow: 'BMYBENCH SENSOR MONITOR',
            title: 'Sensores em tempo real',
            description:
                'Monitoramento contínuo de CPU (total e por núcleo), memória, '
                'temperaturas de CPU e GPU separadas e estado de refrigeração, '
                'atualizados a cada 2 segundos.',
            action: Wrap(
              spacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _paused = !_paused),
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
                  label: Text(_paused ? 'Retomar' : 'Pausar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _tick,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Atualizar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        MetricGrid(
          tiles: [
            MetricTile(
              icon: Icons.memory,
              color: AppColors.accent,
              label: 'Carga da CPU',
              value: s.cpuUsageAvailable
                  ? '${s.cpuUsagePercent.toStringAsFixed(1)}%'
                  : 'N/A',
              caption: !s.cpuUsageAvailable
                  ? 'leitura bloqueada pelo SO'
                  : (s.hasPerCoreLoad
                      ? 'média ${s.perCoreAverage.toStringAsFixed(0)}% em ${s.coreCount} núcleos'
                      : 'amostra a cada 2s'),
              progress: s.cpuUsageAvailable ? s.cpuUsagePercent / 100 : null,
              valueColor: s.cpuUsageAvailable
                  ? AppColors.loadColor(s.cpuUsagePercent)
                  : AppColors.textSecondary,
            ),
            MetricTile(
              icon: Icons.layers_outlined,
              color: AppColors.orange,
              label: 'Memória RAM',
              value: '${s.ramUsagePercent.toStringAsFixed(0)}%',
              caption: '${s.ramUsedLabel} de ${s.ramTotalLabel}',
              progress: s.ramUsagePercent / 100,
              valueColor: AppColors.loadColor(s.ramUsagePercent),
            ),
            MetricTile(
              icon: Icons.thermostat,
              color: _tempColor(s.cpuTemperatureC),
              label: 'Temp. CPU',
              value: _tempLabel(s.cpuTemperatureC),
              caption: _tempCaption(s.cpuTempSource),
              valueColor: _tempColor(s.cpuTemperatureC),
            ),
            MetricTile(
              icon: Icons.videogame_asset_outlined,
              color: _tempColor(s.gpuTemperatureC),
              label: 'Temp. GPU',
              value: _tempLabel(s.gpuTemperatureC),
              caption: _tempCaption(
                s.gpuTempSource,
                extra: s.gpuUsagePercent != null
                    ? '${s.gpuUsagePercent!.toStringAsFixed(0)}% uso'
                    : null,
              ),
              valueColor: _tempColor(s.gpuTemperatureC),
            ),
            MetricTile(
              icon: s.hasFan ? Icons.mode_fan_off : Icons.air,
              color: s.hasFan ? AppColors.violet : AppColors.accent,
              label: s.hasFan ? 'Ventoinha' : 'Arrefecimento',
              value: s.hasFan
                  ? (s.fanRpm != null && s.fanRpm! > 0 ? '${s.fanRpm} RPM' : 'Auto')
                  : 'Passivo',
              caption: [
                s.fanStatus,
                s.thermalState,
                if (s.thermalHeadroom != null)
                  'headroom ${s.thermalHeadroom!.toStringAsFixed(2)}',
              ].join(' · '),
              valueColor: s.hasFan ? AppColors.violet : AppColors.accent,
            ),
          ],
        ),
        const SizedBox(height: 16),
        CpuCoresPanel(snapshot: s),
        const SizedBox(height: 16),
        LineChartPanel(
          title: 'Histórico de CPU',
          legend: 'CPU (%)',
          icon: Icons.show_chart,
          values: _cpuHistory,
          maxValue: 100,
          emptyLabel: 'Coletando amostras...',
          height: 170,
        ),
        const SizedBox(height: 16),
        LineChartPanel(
          title: 'Histórico de memória',
          legend: 'RAM (%)',
          icon: Icons.stacked_line_chart,
          values: _ramHistory,
          maxValue: 100,
          emptyLabel: 'Coletando amostras...',
          color: AppColors.orange,
          height: 170,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _paused ? 'Monitoramento pausado' : 'Atualizando a cada 2 segundos',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
