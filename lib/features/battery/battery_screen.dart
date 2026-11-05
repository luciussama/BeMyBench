import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'battery_service.dart';

class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  final _service = BatteryService();
  BatteryInfo? _info;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final info = await _service.collect();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
        if (info == null) {
          _error = 'Bateria não detectada ou leitura não implementada neste sistema.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _healthColor(double h) {
    if (h >= 90) return AppColors.green;
    if (h >= 80) return AppColors.orange;
    return AppColors.red;
  }

  String _healthLabel(double h) {
    if (h >= 90) return 'Excelente';
    if (h >= 80) return 'Boa';
    if (h >= 70) return 'Degradada';
    return 'Substituir';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final info = _info;
    if (info == null) {
      return Center(
        child: Text(_error.isEmpty ? 'Sem dados de bateria' : _error),
      );
    }

    final color = _healthColor(info.health);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppPanel(
          padding: const EdgeInsets.all(22),
          child: SectionHeader(
            icon: Icons.battery_charging_full,
            eyebrow: 'BMYBENCH BATTERY HEALTH',
            title: 'Diagnóstico da bateria',
            description:
                'Leitura direta do controlador de carga. O teste de descarga completa '
                '(100% → 20%) chega na V1.1.',
            action: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Atualizar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        MetricGrid(
          tiles: [
            MetricTile(
              icon: Icons.percent,
              color: AppColors.accent,
              label: 'Nível',
              value: '${info.percentage}%',
              caption: info.isCharging
                  ? 'carregando'
                  : (info.externalConnected ? 'conectado (AC)' : 'descarregando'),
              progress: info.percentage / 100,
            ),
            MetricTile(
              icon: Icons.favorite_outline,
              color: color,
              label: 'Saúde',
              value: '${info.health.toStringAsFixed(1)}%',
              caption: _healthLabel(info.health),
              valueColor: color,
              progress: info.health / 100,
            ),
            MetricTile(
              icon: Icons.loop,
              color: AppColors.violet,
              label: 'Ciclos',
              value: '${info.cycleCount}',
              caption: 'ciclos de carga completos',
            ),
            MetricTile(
              icon: Icons.bolt,
              color: AppColors.orange,
              label: 'Tensão',
              value: '${(info.voltage / 1000).toStringAsFixed(2)} V',
              caption: 'leitura instantânea',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.table_chart_outlined,
                      size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text(
                    'Capacidades',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _row('Capacidade de projeto', '${info.designCapacity} mAh'),
              _row('Capacidade máxima atual', '${info.maxCapacity} mAh'),
              _row('Carga atual', '${info.currentCapacity} mAh'),
              _row('Ciclos', '${info.cycleCount}'),
              _row('Status', info.isCharging
                  ? 'Carregando'
                  : (info.externalConnected ? 'Conectado (AC)' : 'Descarregando')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
