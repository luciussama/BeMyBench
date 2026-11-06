import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'sensors_service.dart';

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key});

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
                'Monitoramento contínuo de CPU, memória, temperaturas térmicas do SoC '
                'e estado de refrigeração atualizados a cada 2 segundos.',
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
              value: '${s.cpuUsagePercent.toStringAsFixed(1)}%',
              caption: 'amostra a cada 2s',
              progress: s.cpuUsagePercent / 100,
              valueColor: AppColors.loadColor(s.cpuUsagePercent),
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
              color: _tempColor(s.cpuTemperatureC ?? s.temperatureC),
              label: 'Temperatura (CPU/GPU)',
              value: s.cpuTemperatureC != null
                  ? '${s.cpuTemperatureC!.toStringAsFixed(0)} °C'
                  : (s.temperatureC != null
                      ? '${s.temperatureC!.toStringAsFixed(0)} °C'
                      : 'N/A'),
              caption: s.gpuTemperatureC != null
                  ? 'GPU: ${s.gpuTemperatureC!.toStringAsFixed(0)} °C${s.gpuUsagePercent != null ? ' (${s.gpuUsagePercent!.toStringAsFixed(0)}% uso)' : ''} · ${s.thermalState}'
                  : s.thermalState,
              valueColor: _tempColor(s.cpuTemperatureC ?? s.temperatureC),
            ),
            MetricTile(
              icon: s.hasFan ? Icons.mode_fan_off : Icons.air,
              color: s.hasFan ? AppColors.violet : AppColors.accent,
              label: 'Ventoinha',
              value: s.hasFan
                  ? (s.fanRpm != null && s.fanRpm! > 0 ? '${s.fanRpm} RPM' : 'Auto')
                  : 'Passivo',
              caption: s.fanStatus,
              valueColor: s.hasFan ? AppColors.violet : AppColors.accent,
            ),
          ],
        ),
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
