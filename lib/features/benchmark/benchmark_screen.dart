import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/native/native_core.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import '../sensors/sensors_service.dart';
import 'benchmark_models.dart';
import 'benchmark_runner.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final _sensors = SensorsService();

  final Set<String> _selected = {'cpu', 'mem', 'disk'};

  bool _running = false;
  String _current = '';
  String? _error;

  CpuBenchResult? _cpu;
  MemoryBenchResult? _mem;
  DiskBenchResult? _disk;

  int _done = 0;
  int _elapsedSec = 0;
  Timer? _elapsedTimer;
  Timer? _chartTimer;

  final List<double> _cpuHistory = [];

  @override
  void initState() {
    super.initState();
    _startChartSampling();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _chartTimer?.cancel();
    super.dispose();
  }

  void _startChartSampling() {
    _chartTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      try {
        final v = await _sensors.cpuPercentQuick();
        if (!mounted) return;
        setState(() {
          _cpuHistory.add(v);
          if (_cpuHistory.length > 90) _cpuHistory.removeAt(0);
        });
      } catch (_) {}
    });
  }

  double get _totalScore =>
      (_cpu?.score ?? 0) + (_mem?.score ?? 0) + (_disk?.score ?? 0);

  String _fmtScore(double v) {
    if (v >= 100000) return '${(v / 1000).toStringAsFixed(0)}k';
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  String _fmtTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _runAll() async {
    if (_running || _selected.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
      _done = 0;
      _elapsedSec = 0;
      _cpu = null;
      _mem = null;
      _disk = null;
      _current = '';
    });

    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSec++);
    });

    try {
      if (_selected.contains('cpu')) {
        setState(() => _current = 'CPU');
        final r = await BenchmarkRunner.cpu(durationMs: 1000);
        if (!mounted) return;
        setState(() {
          _cpu = r;
          _done++;
        });
      }
      if (_selected.contains('mem')) {
        setState(() => _current = 'Memória');
        final r = await BenchmarkRunner.memory();
        if (!mounted) return;
        setState(() {
          _mem = r;
          _done++;
        });
      }
      if (_selected.contains('disk')) {
        setState(() => _current = 'Disco');
        final r = await BenchmarkRunner.disk();
        if (!mounted) return;
        setState(() {
          _disk = r;
          _done++;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _elapsedTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _running = false;
        _current = '';
      });
    }
  }

  void _toggle(String key) {
    if (_running) return;
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  String get _statusLabel {
    if (_running) return 'EXECUTANDO';
    if (_error != null) return 'ERRO';
    if (_done > 0) return 'CONCLUÍDO';
    return 'PRONTO';
  }

  Color get _statusColor {
    if (_running) return AppColors.orange;
    if (_error != null) return AppColors.red;
    if (_done > 0) return AppColors.green;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final totalTests = _selected.length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ---------------- Cabeçalho + CTA ----------------
        AppPanel(
          padding: const EdgeInsets.all(22),
          child: SectionHeader(
            icon: Icons.bolt,
            eyebrow: 'BMYBENCH STRESS PROTOCOL',
            eyebrowColor: AppColors.accent,
            title: 'Benchmark de hardware',
            description:
                'Executa os testes selecionados em sequência, medindo CPU, memória e disco '
                'com score próprio. O gráfico abaixo mostra a atividade real da CPU.',
            action: GradientActionButton(
              label: _running ? 'EXECUTANDO...' : 'INICIAR TESTES',
              icon: _running ? Icons.hourglass_top : Icons.play_arrow,
              onPressed: _running ? null : _runAll,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------------- Seleção de testes ----------------
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FeatureChip(
              label: 'CPU (inteiros + float)',
              color: AppColors.accent,
              selected: _selected.contains('cpu'),
              enabled: !_running,
              onTap: () => _toggle('cpu'),
            ),
            FeatureChip(
              label: 'Memória (banda + latência)',
              color: AppColors.orange,
              selected: _selected.contains('mem'),
              enabled: !_running,
              onTap: () => _toggle('mem'),
            ),
            FeatureChip(
              label: 'Disco (sequencial)',
              color: AppColors.green,
              selected: _selected.contains('disk'),
              enabled: !_running,
              onTap: () => _toggle('disk'),
            ),
            FeatureChip(
              label: 'GPU (em breve)',
              color: AppColors.violet,
              selected: false,
              enabled: false,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ---------------- Tiles ----------------
        MetricGrid(
          tiles: [
            MetricTile(
              icon: Icons.emoji_events_outlined,
              color: AppColors.accent,
              label: 'Score total',
              value: _done > 0 ? _fmtScore(_totalScore) : '—',
              caption: 'soma dos testes executados',
              valueColor: AppColors.accent,
            ),
            MetricTile(
              icon: Icons.checklist,
              color: AppColors.green,
              label: 'Testes',
              value: '$_done/$totalTests',
              caption: _running ? 'executando $_current' : 'selecionados',
              progress: totalTests == 0 ? 0 : _done / totalTests,
            ),
            MetricTile(
              icon: Icons.timer_outlined,
              color: AppColors.orange,
              label: 'Tempo',
              value: _fmtTime(_elapsedSec),
              caption: _running ? 'em execução' : 'última execução',
            ),
            MetricTile(
              icon: Icons.verified_outlined,
              color: _statusColor,
              label: 'Status',
              value: _statusLabel,
              caption: _error == null
                  ? '${BenchmarkRunner.defaultThreads} threads · Rust ${_safeVersion()}'
                  : 'veja o erro abaixo',
              valueColor: _statusColor,
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_error != null) ...[
          AppPanel(
            color: const Color(0xFF2A1518),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: AppColors.red, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ---------------- Gráfico ----------------
        LineChartPanel(
          title: 'Atividade da CPU',
          legend: 'CPU (%)',
          icon: Icons.monitor_heart_outlined,
          values: _cpuHistory,
          maxValue: 100,
          emptyLabel:
              'Pressione "INICIAR TESTES" para gerar o gráfico dinâmico.',
          height: 190,
        ),
        const SizedBox(height: 16),

        // ---------------- Resultados detalhados ----------------
        if (_done > 0) _ResultsPanel(cpu: _cpu, mem: _mem, disk: _disk),
      ],
    );
  }

  String _safeVersion() {
    try {
      return NativeCore.instance.version;
    } catch (_) {
      return 'n/d';
    }
  }
}

class _ResultsPanel extends StatelessWidget {
  final CpuBenchResult? cpu;
  final MemoryBenchResult? mem;
  final DiskBenchResult? disk;

  const _ResultsPanel({this.cpu, this.mem, this.disk});

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                'Resultados detalhados',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (cpu != null) ...[
            _row('CPU single-core', '${cpu!.singleMops.toStringAsFixed(1)} Mops/s'),
            _row('CPU multi-core (${cpu!.threads} threads)',
                '${cpu!.multiMops.toStringAsFixed(1)} Mops/s'),
            _row('CPU score', cpu!.score.toStringAsFixed(1), strong: true),
          ],
          if (mem != null) ...[
            const Divider(height: 22),
            _row('RAM escrita', '${mem!.writeGbps.toStringAsFixed(2)} GB/s'),
            _row('RAM leitura', '${mem!.readGbps.toStringAsFixed(2)} GB/s'),
            _row('RAM cópia (R+W)', '${mem!.copyGbps.toStringAsFixed(2)} GB/s'),
            _row('RAM latência', '${mem!.latencyNs.toStringAsFixed(1)} ns'),
            _row('Memória score', mem!.score.toStringAsFixed(1), strong: true),
          ],
          if (disk != null) ...[
            const Divider(height: 22),
            _row('Disco escrita', '${disk!.writeMbps.toStringAsFixed(0)} MB/s'),
            _row('Disco leitura', '${disk!.readMbps.toStringAsFixed(0)} MB/s'),
            _row('Disco score', disk!.score.toStringAsFixed(0), strong: true),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: strong ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: strong ? AppColors.accent : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
