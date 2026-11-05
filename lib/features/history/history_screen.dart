import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'bench_record.dart';
import 'history_store.dart';

/// Histórico local dos benchmarks executados.
///
/// Cada execução salva automaticamente com data e resultados por componente.
/// Nada sai da máquina; o arquivo fica no diretório de dados do app.
class HistoryScreen extends StatefulWidget {
  final BenchHistoryStore? store;

  const HistoryScreen({super.key, this.store});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final BenchHistoryStore _store = widget.store ?? BenchHistoryStore();

  List<BenchRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await _store.load();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Apagar histórico?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Todas as execuções salvas serão removidas definitivamente.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _store.clear();
    await _load();
  }

  double get _bestTotal => _records.isEmpty
      ? 0
      : _records.map((r) => r.displayTotal).reduce((a, b) => a > b ? a : b);

  double get _lastTotal => _records.isEmpty ? 0 : _records.last.displayTotal;

  double? get _deltaPercent {
    if (_records.length < 2) return null;
    final previous = _records[_records.length - 2].displayTotal;
    final last = _records.last.displayTotal;
    if (previous <= 0) return null;
    return (last - previous) / previous * 100;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final chartValues = _records.map((r) => r.displayTotal).toList();
    final delta = _deltaPercent;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppPanel(
          padding: const EdgeInsets.all(22),
          child: SectionHeader(
            icon: Icons.history,
            eyebrow: 'BMYBENCH RUN HISTORY',
            title: 'Histórico de benchmarks',
            description:
                'Cada execução é salva automaticamente neste dispositivo. '
                'Compare a evolução dos seus scores ao longo do tempo.',
            action: IconButton(
              tooltip: 'Apagar histórico',
              onPressed: _records.isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_outline),
              color: AppColors.red,
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_records.isEmpty) ...[
          const AppPanel(
            child: SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Nenhuma execução salva ainda.\nRode um benchmark na aba Benchmark.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
          MetricGrid(
            tiles: [
              MetricTile(
                icon: Icons.emoji_events_outlined,
                color: AppColors.accent,
                label: 'Melhor total',
                value: _bestTotal > 0 ? _bestTotal.toStringAsFixed(0) : '—',
                caption: 'melhor execução registrada',
                valueColor: AppColors.accent,
              ),
              MetricTile(
                icon: Icons.flag_outlined,
                color: AppColors.orange,
                label: 'Último total',
                value: _lastTotal > 0 ? _lastTotal.toStringAsFixed(0) : '—',
                caption: 'pontuação da última corrida',
              ),
              MetricTile(
                icon: delta == null || delta >= 0
                    ? Icons.trending_up
                    : Icons.trending_down,
                color: delta == null
                    ? AppColors.textMuted
                    : (delta >= 0 ? AppColors.green : AppColors.red),
                label: 'Variação vs. anterior',
                value: delta == null
                    ? '—'
                    : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
                caption: 'comparado à execução anterior',
                valueColor: delta == null
                    ? AppColors.textSecondary
                    : (delta >= 0 ? AppColors.green : AppColors.red),
              ),
              MetricTile(
                icon: Icons.list_alt,
                color: AppColors.violet,
                label: 'Execuções',
                value: '${_records.length}',
                caption: 'runs salvos localmente',
              ),
            ],
          ),
          const SizedBox(height: 16),

          LineChartPanel(
            title: 'Score total ao longo do tempo',
            legend: 'Score',
            icon: Icons.show_chart,
            values: chartValues,
            maxValue: niceMax(chartValues.reduce((a, b) => a > b ? a : b) * 1.1),
            emptyLabel: 'São necessárias ao menos duas execuções.',
            height: 180,
          ),
          const SizedBox(height: 16),

          for (final record in _records.reversed)
            _RecordRow(
              record: record,
              isBest: record.displayTotal == _bestTotal && _bestTotal > 0,
            ),
        ],
      ],
    );
  }
}

String _fmt(double v) => v.toStringAsFixed(0);

class _RecordRow extends StatelessWidget {
  final BenchRecord record;
  final bool isBest;

  const _RecordRow({required this.record, required this.isBest});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isBest)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.emoji_events_outlined,
                              size: 16, color: AppColors.accent),
                        ),
                      Text(
                        record.dateLabel,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (record.osLabel != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          record.osLabel!,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (record.cpuScore != null)
                        Text('CPU ${_fmt(record.cpuScore!)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      if (record.memScore != null)
                        Text('RAM ${_fmt(record.memScore!)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      if (record.diskScore != null)
                        Text('Disco ${_fmt(record.diskScore!)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      if (record.gpuComputeScore != null)
                        Text('GPU c. ${_fmt(record.gpuComputeScore!)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      if (record.gpuRenderScore != null)
                        Text('GPU r. ${_fmt(record.gpuRenderScore!)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmt(record.displayTotal),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'score total',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
